import Foundation
import SwiftData

/// A single reviewable item — either a bookmarked sentence or a saved word.
/// Wraps the underlying SwiftData model so grading writes straight back to it.
enum ReviewItem: Identifiable {
  case sentence(Sentence)
  case word(SavedWord)

  var id: PersistentIdentifier {
    switch self {
    case let .sentence(s): s.persistentModelID
    case let .word(w): w.persistentModelID
    }
  }

  /// What TTS speaks in the recall phase.
  var promptText: String {
    switch self {
    case let .sentence(s): s.text
    case let .word(w): w.word
    }
  }

  /// The answer revealed after recall.
  var revealText: String {
    switch self {
    case let .sentence(s): s.text
    case let .word(w): w.word
    }
  }

  /// Extra context shown for words only (the sentence they came from).
  var contextText: String? {
    switch self {
    case .sentence: nil
    case let .word(w): w.contextSentence
    }
  }

  /// BCP-47 language for TTS.
  var languageCode: String {
    switch self {
    case let .sentence(s): s.page?.book?.languageCode ?? "en-US"
    case let .word(w): w.languageCode
    }
  }

  /// SRS state, defaulting to a fresh (due-now) state. The setter writes the
  /// mutated value straight back to the underlying model.
  var srs: SRSState {
    get {
      switch self {
      case let .sentence(s): s.srs ?? SRSState()
      case let .word(w): w.srs ?? SRSState()
      }
    }
    nonmutating set {
      switch self {
      case let .sentence(s): s.srs = newValue
      case let .word(w): w.srs = newValue
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
