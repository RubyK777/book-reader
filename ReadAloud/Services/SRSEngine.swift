import Foundation
import SwiftData

/// Which card front a review item gets (PIVOT_PLAN D4: only gradeable modes,
/// routed by item TYPE — intent does not route in v1, D11).
enum CardFace {
  /// Foreign text shown + spoken; recall the meaning. (Words, grammar.)
  case meaning
  /// Audio first, text hidden until reveal. (Sentences.)
  case listening
  /// The context sentence with the saved term blanked out. (Phrases inside
  /// a sentence; falls back to meaning when there is nothing to blank.)
  case cloze
}

/// A single reviewable item — a bookmarked sentence, a saved word (pre-pivot),
/// or a pivot Annotation. Wraps the underlying SwiftData model so grading
/// writes straight back to it.
enum ReviewItem: Identifiable {
  case sentence(Sentence)
  case word(SavedWord)
  case annotation(Annotation)

  var id: PersistentIdentifier {
    switch self {
    case let .sentence(s): s.persistentModelID
    case let .word(w): w.persistentModelID
    case let .annotation(a): a.persistentModelID
    }
  }

  /// What TTS speaks in the recall phase.
  var promptText: String {
    switch self {
    case let .sentence(s): s.text
    case let .word(w): w.word
    case let .annotation(a): a.text
    }
  }

  /// The answer revealed after recall.
  var revealText: String {
    switch self {
    case let .sentence(s): s.text
    case let .word(w): w.word
    case let .annotation(a): a.text
    }
  }

  /// Extra context shown on the answer side (the sentence the item came from).
  var contextText: String? {
    switch self {
    case .sentence: nil
    case let .word(w): w.contextSentence
    case let .annotation(a):
      a.contextSentence == a.text ? nil : a.contextSentence
    }
  }

  /// A translation already persisted for this item (sentences translated in
  /// the Reader). Others translate live on reveal. Used as the flashcard
  /// "answer" (the meaning).
  var existingTranslation: String? {
    switch self {
    case let .sentence(s): s.translatedText
    case .word: nil
    case let .annotation(a):
      a.type == .sentence ? a.sentence?.translatedText : nil
    }
  }

  /// The user's own note, shown on the answer side.
  var note: String? {
    switch self {
    case let .sentence(s): s.userNote
    case let .word(w): w.userNote
    case let .annotation(a): a.userNote
    }
  }

  /// A single word vs. a full sentence — drives front-card typography.
  var isWord: Bool {
    switch self {
    case .word: true
    case let .annotation(a): a.type == .word
    case .sentence: false
    }
  }

  /// BCP-47 language for TTS.
  var languageCode: String {
    switch self {
    case let .sentence(s): s.page?.book?.languageCode ?? "en-US"
    case let .word(w): w.languageCode
    case let .annotation(a): a.languageCode
    }
  }

  /// The blanked context sentence for a cloze front (phrase annotations only).
  var clozeText: String? {
    guard case let .annotation(a) = self, a.type == .phrase else { return nil }
    return ClozeBuilder.blank(term: a.text, in: a.contextSentence)
  }

  /// Card front by item type (D4/D11): words & grammar → meaning; sentences
  /// (bookmarked or annotation) → listening; phrases → cloze when the term
  /// can actually be blanked inside its context sentence.
  var face: CardFace {
    switch self {
    case .sentence: .listening
    case .word: .meaning
    case let .annotation(a):
      switch a.type {
      case .word, .grammar: .meaning
      case .sentence: .listening
      case .phrase:
        ClozeBuilder.blank(term: a.text, in: a.contextSentence) != nil
          ? .cloze : .meaning
      }
    }
  }

  /// SRS state, defaulting to a fresh (due-now) state. The setter writes the
  /// mutated value straight back to the underlying model.
  var srs: SRSState {
    get {
      switch self {
      case let .sentence(s): s.srs ?? SRSState()
      case let .word(w): w.srs ?? SRSState()
      case let .annotation(a): a.srs ?? SRSState()
      }
    }
    nonmutating set {
      switch self {
      case let .sentence(s): s.srs = newValue
      case let .word(w): w.srs = newValue
      case let .annotation(a): a.srs = newValue
      }
    }
  }
}

/// The four grades the reviewer can give, mapped to SM-2 quality scores.
enum ReviewGrade: Int, CaseIterable, Identifiable {
  case again = 1, hard = 3, good = 4, easy = 5

  var id: Int { rawValue }

  var label: String {
    switch self {
    case .again: "Again"
    case .hard: "Hard"
    case .good: "Good"
    case .easy: "Easy"
    }
  }

  /// Coaching hint under each grade — describes the card's fate, not a verdict
  /// on the learner (anti-gamification, DECISIONS #39). The SM-2 grade is unchanged.
  var hint: String {
    switch self {
    case .again: "Show again"
    case .hard: "Barely"
    case .good: "Got it"
    case .easy: "Easy"
    }
  }
}

/// Spaced-repetition scheduling. Pure orchestration over `SRSState.review`.
///
/// `SRSState` is a Codable struct, so `#Predicate` can't reach `srs.dueDate`
/// (DECISIONS #26 / CLAUDE.md) — candidates are fetched, then filtered in memory.
enum SRSEngine {
  /// Bookmarked sentences + all saved words that are due at `now`.
  /// A nil `srs` counts as due (never reviewed).
  @MainActor
  static func dueItems(in context: ModelContext, now: Date = .now) -> [ReviewItem] {
    var items: [ReviewItem] = []

    let sentenceFetch = FetchDescriptor<Sentence>(
      predicate: #Predicate { $0.isBookmarked })
    if let sentences = try? context.fetch(sentenceFetch) {
      items += sentences.map(ReviewItem.sentence)
    }

    let wordFetch = FetchDescriptor<SavedWord>()
    if let words = try? context.fetch(wordFetch) {
      items += words.map(ReviewItem.word)
    }

    let annotationFetch = FetchDescriptor<Annotation>(
      predicate: #Predicate { !$0.isSuspended })
    if let annotations = try? context.fetch(annotationFetch) {
      items += annotations.map(ReviewItem.annotation)
    }

    return items.filter { ($0.srs.dueDate) <= now }
  }

  /// Number of items due at `now`.
  @MainActor
  static func dueCount(in context: ModelContext, now: Date = .now) -> Int {
    dueItems(in: context, now: now).count
  }

  /// Build a capped, shuffled session: overdue-first, take `cap`, then shuffle.
  static func buildSession(from due: [ReviewItem], cap: Int = 20) -> [ReviewItem] {
    due
      .sorted { $0.srs.dueDate < $1.srs.dueDate }
      .prefix(cap)
      .shuffled()
  }

  /// Apply a grade to an item and persist. Writes the new SRS state back to
  /// the underlying model via `ReviewItem.srs`.
  @MainActor
  static func grade(_ item: ReviewItem, _ grade: ReviewGrade, in context: ModelContext) {
    var s = item.srs
    s.review(quality: grade.rawValue)
    item.srs = s
    try? context.save()
  }
}
