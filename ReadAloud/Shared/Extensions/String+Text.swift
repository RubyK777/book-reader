import Foundation

extension Optional where Wrapped == String {
    /// The string, or nil when it's absent or only whitespace. Replaces the
    /// hand-rolled `nonEmpty(_:)` helpers that were copied across screens.
    var nonBlank: String? {
        guard let self, !self.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return self
    }
}

extension StringProtocol {
    /// True when the string is empty or only whitespace.
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

extension String {
    /// The BCP-47 base language subtag, lowercased ("fr-FR" → "fr").
    var languageBase: String { String(prefix(2)).lowercased() }

    /// Whether two language codes share a base language (so there's nothing to
    /// translate between them). Centralizes the source-vs-native guard.
    func hasSameBaseLanguage(as other: String) -> Bool {
        languageBase == other.languageBase
    }

    /// A short title from a text's opening words ("Le petit prince…"). Shared by
    /// the scan-assign flows that auto-title a quick capture.
    static func titleSnippet(from text: String, maxWords: Int = 5) -> String {
        let words = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
        let head = words.prefix(maxWords).joined(separator: " ")
        return words.count > maxWords ? head + "…" : head
    }
}
