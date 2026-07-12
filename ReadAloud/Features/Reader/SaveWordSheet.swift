import SwiftUI
import SwiftData

/// Half-sheet for saving words out of a sentence (UX_SPEC §3). Word chips come
/// from WordTokenizer; tap to toggle any number, then save them all at once.
struct SaveWordSheet: View {
    let sentence: Sentence
    let languageCode: String

    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var selectedWords: Set<String> = []
    @State private var note = ""
    @State private var lookupTerm: DictionaryTerm?

    private let tokenizer = WordTokenizer()

    private var words: [String] {
        tokenizer.words(in: sentence.text, languageCode: languageCode)
    }

    /// Selected words in reading order (for stable save order).
    private var orderedSelection: [String] {
        words.filter { selectedWords.contains($0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                    Text(sentence.text)
                        .font(.body)
                        .foregroundStyle(.secondary)

                    Text("Tap the words you want to save")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    FlowLayout(spacing: DesignSystem.Spacing.sm) {
                        ForEach(words, id: \.self) { word in
                            chip(for: word)
                        }
                    }

                    if orderedSelection.count == 1 {
                        let word = orderedSelection[0]
                        Button {
                            lookupTerm = DictionaryTerm(term: word)
                        } label: {
                            Label("Look Up “\(word)”",
                                  systemImage: DictionaryService.hasDefinition(for: word) ? "book.fill" : "book")
                        }
                        .buttonStyle(.bordered)
                    }

                    if selectedWords.count <= 1 {
                        TextField("Note (optional)", text: $note, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...3)
                    } else {
                        Text("Add notes to individual words later in Saved.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(DesignSystem.Spacing.md)
            }
            .navigationTitle(selectedWords.count > 1 ? "Save Words" : "Save Word")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveLabel) { save() }
                        .disabled(selectedWords.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .dictionaryLookup(term: $lookupTerm)
    }

    private var saveLabel: String {
        switch selectedWords.count {
        case 0: "Save"
        case 1: "Save \(orderedSelection[0])"
        default: "Save \(selectedWords.count)"
        }
    }

    private func chip(for word: String) -> some View {
        let isSelected = selectedWords.contains(word)
        return Button {
            if isSelected { selectedWords.remove(word) } else { selectedWords.insert(word) }
            Haptics.select()
        } label: {
            Text(word)
        }
        .buttonStyle(ChipButtonStyle(isSelected: isSelected))
    }

    private func save() {
        let toSave = orderedSelection
        guard !toSave.isEmpty else { return }

        // Skip words already saved for this language (avoids duplicates when
        // selecting several at once).
        let existing = (try? modelContext.fetch(FetchDescriptor<SavedWord>(
            predicate: #Predicate { $0.languageCode == languageCode })))?
            .map { $0.word.lowercased() } ?? []
        let existingSet = Set(existing)

        let applyNote = toSave.count == 1 && !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        for word in toSave where !existingSet.contains(word.lowercased()) {
            let saved = SavedWord(word: word, contextSentence: sentence.text, languageCode: languageCode)
            saved.srs = SRSState()
            if applyNote { saved.userNote = note }
            modelContext.insert(saved)
        }
        try? modelContext.save()
        router.recomputeDueCount(in: modelContext)
        Haptics.success()
        dismiss()
    }
}

#Preview {
    // Ephemeral preview sentence (not inserted into a container).
    SaveWordSheet(
        sentence: Sentence(text: "Le petit prince regardait le coucher du soleil.", orderIndex: 0),
        languageCode: "fr-FR"
    )
    .environment(AppRouter())
}
