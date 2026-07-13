import Foundation

/// Deterministic cloze construction (PIVOT_PLAN D5): the saved word/phrase IS
/// the blank in its context sentence — no model involved. Pure input → output.
public enum ClozeBuilder {
  /// The mask shown in place of the blanked term.
  public static let mask = "＿＿＿"

  /// `term` blanked out of `sentence` (case- and diacritic-insensitive), or
  /// nil when the term doesn't occur or would blank the whole sentence —
  /// callers fall back to a meaning card.
  public static func blank(term: String, in sentence: String) -> String? {
    let trimmedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedSentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedTerm.isEmpty, !trimmedSentence.isEmpty,
          trimmedTerm.compare(trimmedSentence,
                              options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame
    else { return nil }

    guard let range = trimmedSentence.range(
      of: trimmedTerm,
      options: [.caseInsensitive, .diacriticInsensitive]) else { return nil }

    return trimmedSentence.replacingCharacters(in: range, with: mask)
  }
}
