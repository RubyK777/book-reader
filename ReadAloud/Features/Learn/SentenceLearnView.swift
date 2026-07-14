import SwiftUI
import SwiftData
import Translation
import LearningKit

/// The pivot's heart (product design §7 Phase 2, basic version): study one
/// sentence deeply. Drill-down from a Reader sentence card. Four sections:
/// original + listen controls, translation, Understand (on-device generation
/// with fallback, D1/D2/D7), and one-tap save-as-annotation (D3).
struct SentenceLearnView: View {
    let sentence: Sentence
    let languageCode: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @AppStorage("nativeLanguage") private var nativeLanguage = LanguageCatalog.deviceDefaultNative

    // Short replay player — never owns the lock screen (AUDIO_DESIGN §7).
    @State private var player = SpeechPlayer()
    @State private var isGenerating = false
    @State private var generationFailed = false
    @State private var selectedWords: Set<String> = []
    @State private var selectedIntent: SaveIntent?
    @State private var lookupTerm: DictionaryTerm?
    @State private var isEditingAssets = false
    @State private var confirmDeleteAssets = false
    /// Drives translate-on-save: caches each saved annotation's meaning.
    @State private var translateConfig: TranslationSession.Configuration?
    /// Token lit karaoke-style while its tap-to-hear utterance speaks.
    @State private var speakingTokenIndex: Int?

    private let provider = LearningAssetsProviderFactory.makeDefault()
    private let tokenizer = WordTokenizer()

    private var words: [String] {
        tokenizer.words(in: sentence.text, languageCode: languageCode)
    }

    private var orderedSelection: [String] {
        words.filter { selectedWords.contains($0) }
    }

    private var assets: LearningAssets? { sentence.learningAssets }

    /// UX_SPEC §8: signs/menu lines are phrase-type units — no grammar point,
    /// and whole-item save is a phrase, never a sentence.
    private var isFragment: Bool { FragmentDetector.isFragment(sentence.text) }

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
                requestAnnotationTranslations()
            }
            .onDisappear { player.stop() }
            .task { await generateIfNeeded() }
            .translationTask(translateConfig) { session in
                await translateMissingAnnotations(using: session)
            }
            .dictionaryLookup(term: $lookupTerm)
        }
    }

    // MARK: Original + Listen

    /// Display tokens preserving punctuation — each word is tappable to hear it.
    private var displayTokens: [String] {
        sentence.text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Each token's range within the sentence, for mapping the player's live
    /// word-highlight range onto tokens (karaoke, same as the Reader).
    private var tokenRanges: [NSRange] {
        var ranges: [NSRange] = []
        var cursor = sentence.text.startIndex
        for token in displayTokens {
            if let found = sentence.text.range(of: token, range: cursor..<sentence.text.endIndex) {
                ranges.append(NSRange(found, in: sentence.text))
                cursor = found.upperBound
            } else {
                ranges.append(NSRange(location: NSNotFound, length: 0))
            }
        }
        return ranges
    }

    /// Karaoke state for token `index`: lit while it's the tapped word, or
    /// while full-sentence playback is speaking inside it.
    private func isTokenHighlighted(_ index: Int, ranges: [NSRange]) -> Bool {
        if speakingTokenIndex == index { return true }
        guard player.currentSentenceIndex == 0,
              let highlight = player.highlightRange,
              ranges.indices.contains(index),
              ranges[index].location != NSNotFound else { return false }
        return NSLocationInRange(highlight.location, ranges[index])
    }

    private var originalSection: some View {
        let ranges = tokenRanges
        return VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            FlowLayout(spacing: 6) {
                ForEach(Array(displayTokens.enumerated()), id: \.offset) { index, token in
                    let isLit = isTokenHighlighted(index, ranges: ranges)
                    Button {
                        speakingTokenIndex = index
                        player.speakOnce(token) {
                            if speakingTokenIndex == index { speakingTokenIndex = nil }
                        }
                    } label: {
                        // The hidden bold twin reserves the widest footprint so
                        // bolding on highlight never reflows the line (wiggle room).
                        ZStack {
                            Text(token)
                                .font(Theme.heroFont.weight(.bold))
                                .hidden()
                            Text(token)
                                .font(isLit ? Theme.heroFont.weight(.bold) : Theme.heroFont)
                        }
                        .fontDesign(Theme.sentenceDesign)
                        .padding(.horizontal, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(isLit ? Theme.karaoke : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .animation(.easeOut(duration: 0.12), value: isLit)
                    .accessibilityLabel("\(token) — tap to hear")
                }
            }

            HStack(spacing: DesignSystem.Spacing.sm) {
                Text("Tap any word to hear it · \(LanguageCatalog.name(for: languageCode))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: DesignSystem.Spacing.sm)
                Button {
                    speakingTokenIndex = nil
                    player.speedMultiplier = 1.0
                    player.play(at: 0)   // karaoke via highlightRange
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .fixedSize()

                Button {
                    speakingTokenIndex = nil
                    player.speedMultiplier = 0.5
                    player.play(at: 0)   // slow playback keeps the karaoke too
                } label: {
                    Label("Slow", systemImage: "tortoise.fill")
                }
                .buttonStyle(.bordered)
                .fixedSize()
            }
        }
        .learningCard()
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
                UnderstandContentView(
                    assets: assets,
                    isSaved: { hasAnnotation(text: $0) },
                    onSpeak: { player.speakOnce($0) },
                    onSaveVocab: { saveKeyVocab($0) },
                    onEdit: { isEditingAssets = true },
                    onRegenerate: { Task { await generateIfNeeded(force: true) } },
                    onDelete: { confirmDeleteAssets = true })
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
            } else if provider?.isAvailable == true {
                // Assets were deleted (or the auto-run hasn't fired) — offer it.
                Button {
                    Task { await generateIfNeeded(force: true) }
                } label: {
                    Label("Generate Breakdown", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
            } else {
                fallbackContent
            }
        }
        .sheet(isPresented: $isEditingAssets) {
            if let assets {
                EditAssetsSheet(assets: assets) { edited in
                    var updated = edited
                    updated.userEditedAt = .now
                    sentence.learningAssets = updated
                    try? modelContext.save()
                    Haptics.select()
                }
            }
        }
        .confirmationDialog("Delete this breakdown?",
                            isPresented: $confirmDeleteAssets) {
            Button("Delete Breakdown", role: .destructive) {
                sentence.learningAssets = nil
                try? modelContext.save()
                Haptics.select()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can generate a fresh one afterwards.")
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

                    Button {
                        saveWholeSentence()
                    } label: {
                        Label(wholeSentenceLabel, systemImage: wholeSentenceIcon)
                    }
                    .buttonStyle(.bordered)
                    .disabled(wholeSentenceSaved)
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
        }
        .buttonStyle(ChipButtonStyle(isSelected: isSelected))
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
            SentenceSavedItemsList(
                annotations: sentence.annotations.sorted { $0.savedAt < $1.savedAt })
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
            var generated = try await provider.generateAssets(
                for: sentence.text,
                sourceLanguage: languageCode,
                explanationLanguage: nativeLanguage)
            // UX_SPEC §8: fragments are phrases — never show a grammar point.
            if isFragment { generated.grammarPoint = nil }
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
        if isFragment {
            // UX_SPEC §8: a fragment (sign/menu line) is a phrase, not a starred sentence.
            save(type: .phrase, text: sentence.text)
        } else {
            // Saving a whole sentence *is* starring it — the same as the Reader star.
            starSentence()
        }
    }

    /// Whether the whole-sentence save is already done (starred, or phrase saved).
    private var wholeSentenceSaved: Bool {
        isFragment ? hasAnnotation(text: sentence.text) : sentence.isBookmarked
    }

    private var wholeSentenceLabel: String {
        if isFragment { return wholeSentenceSaved ? "Phrase saved" : "Save phrase" }
        return sentence.isBookmarked ? "Saved" : "Save sentence"
    }

    private var wholeSentenceIcon: String {
        if isFragment { return "bookmark" }
        return sentence.isBookmarked ? "star.fill" : "star"
    }

    private func starSentence() {
        guard !sentence.isBookmarked else { return }
        sentence.setBookmarked(true)
        try? modelContext.save()
        router.recomputeDueCount(in: modelContext)
        Haptics.bookmark()
    }

    /// One-tap save of the generated key vocabulary: each item becomes a word
    /// annotation with its gloss kept as the note. Skips any already saved and
    /// never consumes the optional selection intent (reuse: save path + keyVocab).
    private func saveKeyVocab(_ items: [LearningAssets.VocabItem]) {
        var savedAny = false
        for item in items where !hasAnnotation(text: item.term) {
            let annotation = Annotation(
                type: .word,
                text: item.term,
                contextSentence: sentence.text,
                languageCode: languageCode)
            annotation.userNote = item.meaning
            annotation.srs = SRSState()
            annotation.sentence = sentence
            modelContext.insert(annotation)
            savedAny = true
        }
        guard savedAny else { return }
        try? modelContext.save()
        Haptics.success()
        requestAnnotationTranslations()
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
        requestAnnotationTranslations()
    }

    private func hasAnnotation(text: String) -> Bool {
        sentence.annotations.contains {
            $0.text.compare(text, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    // MARK: Translate-on-save

    /// Kick a translation pass for any saved annotation still missing a meaning,
    /// so the widget/review have it right away. Nil-then-set so the task re-fires
    /// on repeat saves; skipped when the source is already the native language.
    private func requestAnnotationTranslations() {
        guard !languageCode.hasSameBaseLanguage(as: nativeLanguage),
              sentence.annotations.contains(where: { $0.translation == nil }) else { return }
        translateConfig = nil
        Task { @MainActor in
            translateConfig = TranslationSession.Configuration(
                source: Locale.Language(identifier: languageCode),
                target: Locale.Language(identifier: nativeLanguage))
        }
    }

    @MainActor
    private func translateMissingAnnotations(using session: TranslationSession) async {
        let missing = sentence.annotations.filter { $0.translation == nil }
        guard !missing.isEmpty else { return }
        var byID: [String: Annotation] = [:]
        let requests = missing.map { annotation -> TranslationSession.Request in
            let id = "\(annotation.persistentModelID)"
            byID[id] = annotation
            return TranslationSession.Request(sourceText: annotation.text, clientIdentifier: id)
        }
        guard let responses = try? await session.translations(from: requests) else { return }
        for response in responses {
            if let annotation = byID[response.clientIdentifier ?? ""], !response.targetText.isEmpty {
                annotation.translation = response.targetText
            }
        }
        try? modelContext.save()
    }

    // MARK: Section chrome

    private func sectionCard(_ title: String, systemImage: String,
                             @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            SectionHeaderLabel(title: title, systemImage: systemImage)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .learningCard()
    }
}

#Preview {
    SentenceLearnView(
        sentence: Sentence(text: "Je n'arrive pas à y croire.", orderIndex: 0),
        languageCode: "fr-FR"
    )
}
