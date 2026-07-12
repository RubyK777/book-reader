import SwiftUI
import SwiftData

/// The Notebook (PIVOT_PLAN Phase 4): saved annotations with type/confused
/// filters, plus the legacy per-item notes browser in a second segment.
struct NotesView: View {
    private enum Segment: Hashable { case notebook, legacy }

    /// Notebook type filter — nil = all types.
    private enum TypeFilter: Hashable, CaseIterable {
        case all, word, phrase, sentence, grammar, confused

        var label: String {
            switch self {
            case .all: "All"
            case .word: "Words"
            case .phrase: "Phrases"
            case .sentence: "Sentences"
            case .grammar: "Grammar"
            case .confused: "Confused"
            }
        }
    }

    @Query(sort: \Annotation.savedAt, order: .reverse)
    private var annotations: [Annotation]

    @Query(filter: #Predicate<SavedWord> { $0.userNote != nil },
           sort: \SavedWord.savedAt, order: .reverse)
    private var notedWords: [SavedWord]

    @Query(filter: #Predicate<Sentence> { $0.userNote != nil })
    private var notedSentences: [Sentence]

    @State private var search = ""
    @State private var segment: Segment = .notebook
    @State private var typeFilter: TypeFilter = .all

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var filteredAnnotations: [Annotation] {
        annotations.filter { annotation in
            let passesType: Bool = switch typeFilter {
            case .all: true
            case .word: annotation.type == .word
            case .phrase: annotation.type == .phrase
            case .sentence: annotation.type == .sentence
            case .grammar: annotation.type == .grammar
            case .confused: annotation.isConfusing && !annotation.isResolved
            }
            guard passesType else { return false }
            guard !search.isEmpty else { return true }
            return annotation.text.localizedCaseInsensitiveContains(search)
                || annotation.contextSentence.localizedCaseInsensitiveContains(search)
                || annotation.userNote?.localizedCaseInsensitiveContains(search) == true
                || annotation.userExample?.localizedCaseInsensitiveContains(search) == true
                || annotation.tags.contains { $0.localizedCaseInsensitiveContains(search) }
        }
    }

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
                switch segment {
                case .notebook: notebookList
                case .legacy: legacyList
                }
            }
            .navigationTitle("Notebook")
            .searchable(text: $search, prompt: segment == .notebook ? "Search saved items" : "Search notes")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Section", selection: $segment) {
                        Text("Notebook").tag(Segment.notebook)
                        Text("Item notes").tag(Segment.legacy)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                }
            }
            .navigationDestination(for: Entry.self) { entry in
                switch entry.kind {
                case let .word(word): SavedItemDetailView(word: word)
                case let .sentence(sentence): SavedItemDetailView(sentence: sentence)
                }
            }
            .navigationDestination(for: PersistentIdentifier.self) { id in
                if let annotation = annotations.first(where: { $0.persistentModelID == id }) {
                    AnnotationDetailView(annotation: annotation)
                }
            }
        }
    }

    // MARK: Notebook segment

    @ViewBuilder
    private var notebookList: some View {
        if annotations.isEmpty {
            AnimatedEmptyState(
                title: "Your notebook is empty",
                message: "Words, phrases, and sentences you save while reading gather here — with your notes and examples.",
                systemImage: "bookmark",
                tint: Theme.accent)
        } else {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        ForEach(TypeFilter.allCases, id: \.self) { filter in
                            Button {
                                withAnimation(.snappy(duration: 0.3)) {
                                    typeFilter = filter
                                }
                                Haptics.select()
                            } label: {
                                Text(filter.label)
                            }
                            .buttonStyle(ChipButtonStyle(isSelected: typeFilter == filter,
                                                         tint: tint(for: filter)))
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                }

                if filteredAnnotations.isEmpty {
                    AnimatedEmptyState(
                        title: "Nothing here yet",
                        message: "No saved items match this filter — try another, or clear your search.",
                        systemImage: "line.3.horizontal.decrease.circle",
                        tint: Theme.slate)
                } else {
                    ScrollView {
                        LazyVStack(spacing: DesignSystem.Spacing.sm) {
                            ForEach(filteredAnnotations) { annotation in
                                NavigationLink(value: annotation.persistentModelID) {
                                    scrollAnimated(
                                        annotationRow(annotation)
                                            .learningCard()
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, DesignSystem.Spacing.md)
                        .padding(.vertical, DesignSystem.Spacing.sm)
                    }
                }
            }
        }
    }

    /// Per-filter chip tint — annotation types own their palette hue; the
    /// confused state is marigold, "All" is the ink accent.
    private func tint(for filter: TypeFilter) -> Color {
        switch filter {
        case .all: Theme.accent
        case .word: AnnotationType.word.tint
        case .phrase: AnnotationType.phrase.tint
        case .sentence: AnnotationType.sentence.tint
        case .grammar: AnnotationType.grammar.tint
        case .confused: Theme.marigold
        }
    }

    /// Applies the interactive edge fade/scale to a card — skipped entirely
    /// under Reduce Motion (`.scrollTransition` also no-ops inside `List`,
    /// which is why the notebook uses a `ScrollView`).
    @ViewBuilder
    private func scrollAnimated<Card: View>(_ card: Card) -> some View {
        if reduceMotion {
            card
        } else {
            card.scrollTransition(.interactive) { content, phase in
                content
                    .opacity(phase.isIdentity ? 1 : 0.5)
                    .scaleEffect(phase.isIdentity ? 1 : 0.96)
            }
        }
    }

    private func annotationRow(_ annotation: Annotation) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Capsule()
                .fill(annotation.type.tint)
                .frame(width: DesignSystem.Spacing.xs)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Text(annotation.type.rawValue)
                        .font(.caption2.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.accent)
                    if annotation.isConfusing && !annotation.isResolved {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.marigold)
                            .accessibilityLabel("Confused")
                    }
                    if annotation.isSuspended {
                        Image(systemName: "pause.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Suspended")
                    }
                    if let intent = annotation.intent {
                        Text(intent.displayName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(annotation.text)
                    .font(.body)
                    .fontDesign(Theme.sentenceDesign)
                    .lineLimit(2)

                if annotation.contextSentence != annotation.text {
                    Text(annotation.contextSentence)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Legacy segment

    @ViewBuilder
    private var legacyList: some View {
        if entries.isEmpty {
            emptyState
        } else {
            List(entries) { entry in
                NavigationLink(value: entry) { row(entry) }
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
        AnimatedEmptyState(
            title: search.isEmpty ? "No notes yet" : "No matching notes",
            message: search.isEmpty
                ? "Add a note when you save a word, or on any saved item's detail — they all collect here."
                : "Try a different search.",
            systemImage: "note.text",
            tint: Theme.slate)
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
