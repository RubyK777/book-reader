import SwiftUI
import SwiftData
import Translation

/// Detail for one saved item — a word or a bookmarked sentence. Shows the full
/// text, its meaning (translated into the native language), a replay button,
/// the source context (words only), an editable note (autosaved), the SRS
/// schedule, and a destructive removal action. A word is deleted outright; a
/// sentence only loses its bookmark (its SRS state is kept).
struct SavedItemDetailView: View {
  private enum Item {
    case word(SavedWord)
    case sentence(Sentence)
  }

  /// Meaning (translation into the native language) for this item.
  private enum Meaning: Equatable { case none, translating, ready(String), unavailable }

  @Environment(\.modelContext) private var modelContext
  @Environment(AppRouter.self) private var router
  @Environment(\.dismiss) private var dismiss
  @AppStorage("nativeLanguage") private var nativeLanguage = LanguageCatalog.deviceDefaultNative

  private let item: Item
  @State private var player = SpeechPlayer()
  @State private var isConfirmingRemoval = false
  @State private var meaning: Meaning = .none
  @State private var translateConfig: TranslationSession.Configuration?
  @State private var lookupTerm: DictionaryTerm?

  private var isWord: Bool {
    if case .word = item { return true }
    return false
  }

  init(word: SavedWord) { item = .word(word) }
  init(sentence: Sentence) { item = .sentence(sentence) }

  var body: some View {
    Form {
      Section {
        Text(text)
          .font(.title3.weight(.semibold))
        if let dateText {
          Text("\(sourceLabel) · \(dateText)")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Button {
          player.load(sentences: [text], languageCode: languageCode)
          player.play(at: 0)
          Haptics.select()
        } label: {
          Label("Play", systemImage: "speaker.wave.2.fill")
        }
        if isWord {
          Button {
            lookupTerm = DictionaryTerm(term: text)
          } label: {
            Label("Look Up", systemImage: DictionaryService.hasDefinition(for: text) ? "book.fill" : "book")
          }
        }
      }

      meaningSection

      if let contextText {
        Section("Context") {
          Text(contextText)
            .foregroundStyle(.secondary)
        }
      }

      Section("Note") {
        TextField("Add a note", text: noteBinding, axis: .vertical)
          .lineLimit(1...4)
      }

      Section("Review") {
        LabeledContent("Repetitions", value: "\(srs.repetitions)")
        LabeledContent("Ease", value: srs.easeFactor.formatted(.number.precision(.fractionLength(1))))
        LabeledContent("Interval", value: "\(srs.intervalDays) day\(srs.intervalDays == 1 ? "" : "s")")
        LabeledContent("Due", value: srs.dueDate.formatted(.relative(presentation: .named)))
      }

      Section {
        Button(role: .destructive) { isConfirmingRemoval = true } label: {
          Label(removalActionLabel, systemImage: removalIcon)
        }
      }
    }
    .navigationTitle(navTitle)
    .navigationBarTitleDisplayMode(.inline)
    .confirmationDialog(
      removalPrompt,
      isPresented: $isConfirmingRemoval,
      titleVisibility: .visible
    ) {
      Button(removalActionLabel, role: .destructive) { performRemoval() }
      Button("Cancel", role: .cancel) {}
    }
    .task { resolveMeaning() }
    .translationTask(translateConfig) { session in
      await translate(using: session)
    }
    .sheet(item: $lookupTerm) { lookup in
      DictionaryView(term: lookup.term).ignoresSafeArea()
    }
  }

  /// The translated meaning, once resolved. Hidden when the item is already in
  /// the native language or no translation is available.
  @ViewBuilder
  private var meaningSection: some View {
    switch meaning {
    case .translating:
      Section("Meaning") {
        HStack(spacing: DesignSystem.Spacing.sm) {
          ProgressView().controlSize(.small)
          Text("Translating…").foregroundStyle(.secondary)
        }
      }
    case let .ready(translated):
      Section("Meaning") {
        Text(translated).font(.body)
      }
    case .none, .unavailable:
      EmptyView()
    }
  }

  /// Resolve the meaning: reuse a stored sentence translation, skip when the
  /// item is already the native language, else translate live into it.
  private func resolveMeaning() {
    guard meaning == .none else { return }
    if case let .sentence(s) = item, let stored = s.translatedText, !stored.isEmpty {
      meaning = .ready(stored)
      return
    }
    let sourceBase = String(languageCode.prefix(2)).lowercased()
    let nativeBase = String(nativeLanguage.prefix(2)).lowercased()
    guard sourceBase != nativeBase else { meaning = .unavailable; return }
    meaning = .translating
    translateConfig = TranslationSession.Configuration(
      source: Locale.Language(identifier: languageCode),
      target: Locale.Language(identifier: nativeLanguage))
  }

  @MainActor
  private func translate(using session: TranslationSession) async {
    do {
      let responses = try await session.translations(
        from: [TranslationSession.Request(sourceText: text)])
      if let translated = responses.first?.targetText, !translated.isEmpty {
        meaning = .ready(translated)
        // Persist for sentences (they have a field); words translate live only.
        if case let .sentence(s) = item, s.translatedText == nil {
          s.translatedText = translated
          try? modelContext.save()
        }
      } else {
        meaning = .unavailable
      }
    } catch {
      meaning = .unavailable
    }
  }

  // MARK: - Accessors

  private var text: String {
    switch item {
    case let .word(w): w.word
    case let .sentence(s): s.text
    }
  }

  private var languageCode: String {
    switch item {
    case let .word(w): w.languageCode
    case let .sentence(s): s.page?.book?.languageCode ?? "en-US"
    }
  }

  private var contextText: String? {
    switch item {
    case let .word(w): w.contextSentence
    case .sentence: nil
    }
  }

  private var srs: SRSState {
    switch item {
    case let .word(w): w.srs ?? SRSState()
    case let .sentence(s): s.srs ?? SRSState()
    }
  }

  private var sourceLabel: String {
    LanguageCatalog.name(for: languageCode)
  }

  private var dateText: String? {
    switch item {
    case let .word(w): w.savedAt.formatted(.dateTime.month().day().year())
    case let .sentence(s): s.page?.scannedAt.formatted(.dateTime.month().day().year())
    }
  }

  private var noteBinding: Binding<String> {
    Binding(
      get: {
        switch item {
        case let .word(w): w.userNote ?? ""
        case let .sentence(s): s.userNote ?? ""
        }
      },
      set: { newValue in
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let stored: String? = trimmed.isEmpty ? nil : newValue
        switch item {
        case let .word(w): w.userNote = stored
        case let .sentence(s): s.userNote = stored
        }
      }
    )
  }

  // MARK: - Removal labels

  private var navTitle: String {
    switch item {
    case .word: "Word"
    case .sentence: "Sentence"
    }
  }

  private var removalActionLabel: String {
    switch item {
    case .word: "Delete Word"
    case .sentence: "Remove from Saved"
    }
  }

  private var removalIcon: String {
    switch item {
    case .word: "trash"
    case .sentence: "bookmark.slash"
    }
  }

  private var removalPrompt: String {
    switch item {
    case .word: "Delete this word?"
    case .sentence: "Remove this sentence from Saved?"
    }
  }

  // MARK: - Mutations

  private func performRemoval() {
    switch item {
    case let .word(w):
      modelContext.delete(w)
    case let .sentence(s):
      s.isBookmarked = false   // keep SRS state; never delete the sentence here
    }
    try? modelContext.save()
    router.recomputeDueCount(in: modelContext)
    dismiss()
  }
}
