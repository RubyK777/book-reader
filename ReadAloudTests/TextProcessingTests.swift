import Testing
@testable import ReadAloud

/// Sentence splitting and word tokenization — the text pipeline feeding the
/// Reader and Save-Word sheet.
struct TextProcessingTests {
    let splitter = SentenceSplitter()
    let tokenizer = WordTokenizer()

    @Test func splitsTwoEnglishSentences() {
        let parts = splitter.split("Hello world. How are you?", languageCode: "en-US")
        #expect(parts == ["Hello world.", "How are you?"])
    }

    @Test func emptyTextYieldsNoSentences() {
        #expect(splitter.split("", languageCode: "en-US").isEmpty)
        #expect(splitter.split("   \n  ", languageCode: "en-US").isEmpty)
    }

    @Test func singleSentenceWithoutTerminatorStaysWhole() {
        let parts = splitter.split("Le petit prince", languageCode: "fr-FR")
        #expect(parts == ["Le petit prince"])
    }

    @Test func trimsWhitespaceAroundSentences() {
        let parts = splitter.split("  Un. Deux.  ", languageCode: "fr-FR")
        #expect(parts == ["Un.", "Deux."])
    }

    @Test func tokenizesWordsInOrder() {
        let words = tokenizer.words(in: "Le petit prince", languageCode: "fr-FR")
        #expect(words == ["Le", "petit", "prince"])
    }

    @Test func dedupesCaseInsensitivelyKeepingFirstOccurrence() {
        // "Il" and "il", "le" twice — keep the first occurrence and its casing.
        let words = tokenizer.words(in: "Il le vit et il le prit", languageCode: "fr-FR")
        #expect(words == ["Il", "le", "vit", "et", "prit"])
    }

    @Test func dropsPunctuationTokens() {
        let words = tokenizer.words(in: "cat, dog!", languageCode: "en-US")
        #expect(words == ["cat", "dog"])
    }
}
