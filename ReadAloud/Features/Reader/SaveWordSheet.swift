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
                .font(.callout)
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .background(
                    Capsule().fill(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
                )
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
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

/// Wrapping (left-to-right, top-to-bottom) layout for word chips.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [CGFloat] = [0]        // width used per row
        var rowHeights: [CGFloat] = [0]
        var x: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + spacing + size.width > maxWidth {
                rows.append(0)
                rowHeights.append(0)
                x = 0
            }
            x += (x > 0 ? spacing : 0) + size.width
            rows[rows.count - 1] = x
            rowHeights[rowHeights.count - 1] = max(rowHeights[rowHeights.count - 1], size.height)
        }

        let totalHeight = rowHeights.reduce(0, +) + spacing * CGFloat(max(0, rowHeights.count - 1))
        let totalWidth = rows.max() ?? 0
        return CGSize(width: min(totalWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.minX + maxWidth {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
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
