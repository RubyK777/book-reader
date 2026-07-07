import Foundation
import NaturalLanguage

/// Splits a sentence into distinct words for the Save-Word chip picker.
struct WordTokenizer {
    /// Words in first-occurrence order, deduped case-insensitively but keeping original casing.
    func words(in sentence: String, languageCode: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.setLanguage(NLLanguage(rawValue: String(languageCode.prefix(2))))
        tokenizer.string = sentence

        var result: [String] = []
        var seen: Set<String> = []
        tokenizer.enumerateTokens(in: sentence.startIndex..<sentence.endIndex) { range, _ in
            let word = String(sentence[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty else { return true }
            let key = word.lowercased()
            if seen.insert(key).inserted { result.append(word) }
            return true
        }
        return result
    }
}
