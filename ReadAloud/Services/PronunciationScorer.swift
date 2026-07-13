import Foundation

/// One target word and whether the learner said it recognizably.
struct WordMatch: Equatable {
    let text: String
    let matched: Bool
}

/// The outcome of comparing a spoken attempt to the target sentence. Anti-
/// gamification (DECISIONS #39): the UI shows "words to revisit", never a score.
struct PronunciationResult: Equatable {
    let passed: Bool
    let words: [WordMatch]
    let ratio: Double

    var missedWords: [String] { words.filter { !$0.matched }.map(\.text) }
}

/// Compares an on-device transcript of the learner's speech to the target text
/// (AUDIO_LEARNING_DESIGN §9 / PIVOT §7 pronunciation-compare). Case- and
/// diacritic-insensitive word alignment (LCS) marks each target word matched or
/// missed; it passes when enough words line up. Pure + testable.
enum PronunciationScorer {
    static func score(target: String, heard: String, passRatio: Double = 0.6) -> PronunciationResult {
        let targetTokens = tokenize(target)
        let heardKeys = tokenize(heard).map(\.key)
        let flags = matchFlags(targetKeys: targetTokens.map(\.key), heardKeys: heardKeys)

        let words = zip(targetTokens, flags).map { WordMatch(text: $0.0.display, matched: $0.1) }
        let matched = flags.filter { $0 }.count
        let ratio = targetTokens.isEmpty ? 0 : Double(matched) / Double(targetTokens.count)
        return PronunciationResult(passed: !targetTokens.isEmpty && ratio >= passRatio,
                                   words: words, ratio: ratio)
    }

    /// Words as (display, folded key) — key ignores case, diacritics, punctuation.
    private static func tokenize(_ text: String) -> [(display: String, key: String)] {
        var result: [(String, String)] = []
        let ns = text as NSString
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length),
                               options: .byWords) { substring, _, _, _ in
            guard let substring else { return }
            let key = substring.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            result.append((substring, key))
        }
        return result
    }

    /// Which target tokens belong to the longest common subsequence with the
    /// heard tokens — i.e. the words the learner actually said, in order.
    private static func matchFlags(targetKeys: [String], heardKeys: [String]) -> [Bool] {
        let n = targetKeys.count, m = heardKeys.count
        guard n > 0, m > 0 else { return Array(repeating: false, count: n) }

        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                dp[i][j] = targetKeys[i] == heardKeys[j]
                    ? 1 + dp[i + 1][j + 1]
                    : max(dp[i + 1][j], dp[i][j + 1])
            }
        }

        var flags = Array(repeating: false, count: n)
        var i = 0, j = 0
        while i < n && j < m {
            if targetKeys[i] == heardKeys[j] {
                flags[i] = true
                i += 1; j += 1
            } else if dp[i + 1][j] >= dp[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return flags
    }
}
