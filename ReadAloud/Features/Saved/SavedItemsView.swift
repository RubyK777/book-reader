import SwiftUI
import SwiftData

/// Browser for everything the user has saved: vocabulary words and bookmarked
/// sentences, split across a segmented "Words | Sentences" picker (UX_SPEC §2).
/// Each row replays its text via a shared `SpeechPlayer` and pushes a detail
/// view. Removing a sentence only clears its bookmark (its SRS state is kept).
struct SavedItemsView: View {
  private enum Tab: Hashable { case words, sentences }

  @Environment(\.modelContext) private var modelContext
  @Environment(AppRouter.self) private var router

  @Query(sort: \SavedWord.savedAt, order: .reverse)
  private var words: [SavedWord]

  @Query(filter: #Predicate<Sentence> { $0.isBookmarked })
  private var sentences: [Sentence]

  @State private var tab: Tab = .words
  @State private var player = SpeechPlayer()

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        Picker("View", selection: $tab) {
          Text("Words").tag(Tab.words)
          Text("Sentences").tag(Tab.sentences)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)

        switch tab {
        case .words: wordsList
        case .sentences: sentencesList
        }
      }
      .navigationTitle("Saved")
      .navigationDestination(for: SavedWord.self) { SavedItemDetailView(word: $0) }
      .navigationDestination(for: Sentence.self) { SavedItemDetailView(sentence: $0) }
    }
  }

  // MARK: - Words

  @ViewBuilder
  private var wordsList: some View {
    if words.isEmpty {
      ContentUnavailableView(
        "No Saved Words",
        systemImage: "textformat.abc",
        description: Text("Long-press a sentence in the Reader, then pick a word"))
    } else {
      List {
        ForEach(words) { word in
          NavigationLink(value: word) {
            row(text: word.word, code: word.languageCode, date: word.savedAt)
          }
          .swipeActions(edge: .trailing) {
            Button(role: .destructive) { delete(word) } label: {
              Label("Delete", systemImage: "trash")
            }
          }
        }
      }
    }
  }

  // MARK: - Sentences

  @ViewBuilder
  private var sentencesList: some View {
    if sentences.isEmpty {
      ContentUnavailableView(
        "No Saved Sentences",
        systemImage: "bookmark",
        description: Text("Star a sentence in the Reader"))
    } else {
      List {
        ForEach(sortedSentences) { sentence in
          let code = sentence.page?.book?.languageCode ?? "en-US"
          NavigationLink(value: sentence) {
            row(text: sentence.text, code: code, date: sentence.page?.scannedAt)
          }
          .swipeActions(edge: .trailing) {
            Button(role: .destructive) { removeFromSaved(sentence) } label: {
              Label("Remove from Saved", systemImage: "bookmark.slash")
            }
          }
        }
      }
    }
  }

  /// Bookmarked sentences ordered by book, then page, then position in page.
  private var sortedSentences: [Sentence] {
    sentences.sorted {
      (($0.page?.book?.createdAt ?? .distantPast), ($0.page?.orderIndex ?? 0), $0.orderIndex)
        < (($1.page?.book?.createdAt ?? .distantPast), ($1.page?.orderIndex ?? 0), $1.orderIndex)
    }
  }

  // MARK: - Row

  private func row(text: String, code: String, date: Date?) -> some View {
    HStack(spacing: DesignSystem.Spacing.md) {
      VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
        Text(text)
          .font(.body)
          .lineLimit(2)
        Text(caption(code: code, date: date))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: DesignSystem.Spacing.sm)
      replayButton(text: text, code: code)
    }
  }

  private func caption(code: String, date: Date?) -> String {
    let name = LanguageCatalog.name(for: code)
    guard let date else { return name }
    return "\(name) · \(date.formatted(.dateTime.month().day().year()))"
  }

  private func replayButton(text: String, code: String) -> some View {
    Button {
      player.load(sentences: [text], languageCode: code)
      player.play(at: 0)
      Haptics.select()
    } label: {
      Image(systemName: "speaker.wave.2.fill")
        .font(.title3)
        .foregroundStyle(Color.accentColor)
        .frame(width: DesignSystem.minTapTarget, height: DesignSystem.minTapTarget)
    }
    .buttonStyle(.borderless)
    .accessibilityLabel("Play")
  }

  // MARK: - Mutations

  private func delete(_ word: SavedWord) {
    modelContext.delete(word)
    try? modelContext.save()
    router.recomputeDueCount(in: modelContext)
  }

  /// Clears the bookmark only — the sentence and its SRS state are preserved.
  private func removeFromSaved(_ sentence: Sentence) {
    sentence.isBookmarked = false
    try? modelContext.save()
    router.recomputeDueCount(in: modelContext)
  }
}
