import SwiftUI
import SwiftData

/// Edit a single sentence's text. Clears its stale translation on save; the
/// Reader reloads the player queue via `onSaved`.
struct EditSentenceSheet: View {
    let sentence: Sentence
    let onSaved: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(sentence: Sentence, onSaved: @escaping () -> Void) {
        self.sentence = sentence
        self.onSaved = onSaved
        _text = State(initialValue: sentence.text)
    }

    private var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Sentence") {
                    TextEditor(text: $text)
                        .frame(minHeight: 140)
                }
            }
            .navigationTitle("Edit Sentence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sentence.text = trimmed
        sentence.translatedText = nil   // translation is stale after an edit
        try? modelContext.save()
        onSaved()
        Haptics.select()
        dismiss()
    }
}
