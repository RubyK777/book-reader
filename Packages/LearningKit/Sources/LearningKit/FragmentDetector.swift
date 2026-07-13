import Foundation

/// UX_SPEC §8 fragment rule: real-world scans (signs, menus, labels) yield
/// lines that aren't sentences — they become phrase-type learning units.
/// Pure input → output; thresholds tuned against the 0.2 fixtures.
public enum FragmentDetector {
    /// Characters that close a real sentence (Latin scripts + CJK terminals).
    private static let terminators: Set<Character> = [".", "!", "?", "…", "。", "！", "？"]

    /// A token is "symbolic" when most of its characters are digits, currency,
    /// or punctuation — prices ("14€"), times ("9h–18h"), codes.
    private static func isSymbolic(_ token: Substring) -> Bool {
        let scalars = token.unicodeScalars
        guard !scalars.isEmpty else { return false }
        let symbolic = scalars.count {
            CharacterSet.decimalDigits.contains($0)
                || CharacterSet.symbols.contains($0)
                || CharacterSet.punctuationCharacters.contains($0)
        }
        return symbolic * 2 >= scalars.count
    }

    /// True when `text` should be treated as a phrase, not a sentence:
    /// no terminal punctuation AND under ~6 words, OR mostly numerals/symbols/prices.
    public static func isFragment(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return false }

        let tokens = trimmed.split(whereSeparator: \.isWhitespace)
        guard !tokens.isEmpty else { return false }

        let symbolicTokens = tokens.count(where: isSymbolic)
        if symbolicTokens * 2 >= tokens.count { return true }

        return !terminators.contains(last) && tokens.count < 6
    }
}
