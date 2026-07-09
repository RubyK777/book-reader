import SwiftUI
import SwiftData

/// Every note in one place: notes attached to saved words and bookmarked
/// sentences, searchable, each tappable through to its detail for editing.
struct NotesView: View {
    @Query(filter: #Predicate<SavedWord> { $0.userNote != nil },
           sort: \SavedWord.savedAt, order: .reverse)
    private var notedWords: [SavedWord]

    @Query(filter: #Predicate<Sentence> { $0.userNote != nil })
    private var notedSentences: [Sentence]

    @State private var search = ""

    /// A note plus the item it belongs to, for a unified list.
    fileprivate struct Entry: Identifiable {
        enum Kind { case word(SavedWord), sentence(Sentence) }
        let id: PersistentIdentifier
        let note: String
        let term: String
        let languageCode: String
        let date: Date
        let kind: Kind
    }

    private var entries: [Entry] {
        var out: [Entry] = []
        for word in notedWords {
            guard let note = nonEmpty(word.userNote) else { continue }
            out.append(Entry(id: word.persistentModelID, note: note, term: word.word,
                             languageCode: word.languageCode, date: word.savedAt, kind: .word(word)))
        }
        for sentence in notedSentences {
            guard let note = nonEmpty(sentence.userNote) else { continue }
            out.append(Entry(id: sentence.persistentModelID, note: note, term: sentence.text,
                             languageCode: sentence.page?.book?.languageCode ?? "en-US",
                             date: sentence.page?.scannedAt ?? .distantPast, kind: .sentence(sentence)))
        }
        let filtered = search.isEmpty ? out : out.filter {
            $0.note.localizedCaseInsensitiveContains(search)
                || $0.term.localizedCaseInsensitiveContains(search)
        }
        return filtered.sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    emptyState
                } else {
                    List(entries) { entry in
                        NavigationLink(value: entry) { row(entry) }
                    }
                }
            }
            .navigationTitle("Notes")
            .searchable(text: $search, prompt: "Search notes")
            .navigationDestination(for: Entry.self) { entry in
                switch entry.kind {
                case let .word(word): SavedItemDetailView(word: word)
                case let .sentence(sentence): SavedItemDetailView(sentence: sentence)
                }
            }
        }
    }

    private func row(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text(entry.note)
                .font(.body)
                .lineLimit(3)
            Text("\(entry.term) · \(LanguageCatalog.name(for: entry.languageCode))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            search.isEmpty ? "No notes yet" : "No matching notes",
            systemImage: "note.text",
            description: Text(search.isEmpty
                ? "Add a note when you save a word, or on any saved item's detail — they all collect here."
                : "Try a different search."))
    }

    private func nonEmpty(_ string: String?) -> String? {
        guard let string, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return string
    }
}

extension NotesView.Entry: Hashable {
    static func == (lhs: NotesView.Entry, rhs: NotesView.Entry) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
