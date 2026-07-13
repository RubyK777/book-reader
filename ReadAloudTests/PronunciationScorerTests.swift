import Testing
@testable import ReadAloud

struct PronunciationScorerTests {
    @Test func exactMatchPasses() {
        let result = PronunciationScorer.score(target: "le petit prince", heard: "le petit prince")
        #expect(result.passed)
        #expect(result.words.allSatisfy { $0.matched })
        #expect(result.missedWords.isEmpty)
    }

    @Test func caseAndDiacriticInsensitive() {
        let result = PronunciationScorer.score(target: "Ça va bien", heard: "ca va bien")
        #expect(result.passed)
        #expect(result.missedWords.isEmpty)
    }

    @Test func marksMissedWords() {
        let result = PronunciationScorer.score(target: "le petit prince", heard: "le prince")
        #expect(result.missedWords == ["petit"])
        #expect(abs(result.ratio - 2.0 / 3.0) < 0.001)
    }

    @Test func mostlyWrongFails() {
        let result = PronunciationScorer.score(target: "le petit prince vivait seul", heard: "bonjour")
        #expect(!result.passed)
    }

    @Test func emptyAttemptFails() {
        let result = PronunciationScorer.score(target: "bonjour tout le monde", heard: "")
        #expect(!result.passed)
        #expect(result.missedWords.count == 4)
    }
}
