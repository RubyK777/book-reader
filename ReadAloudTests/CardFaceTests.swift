import Foundation
import Testing
@testable import ReadAloud

/// Review card-front routing (`SRSEngine.ReviewItem.face`, D4/D11): the item's
/// TYPE picks the front, and a phrase only becomes a cloze when its term can be
/// blanked inside its context sentence — otherwise it degrades to `.meaning`.
/// These are the branches the "say your answer" speech-check rides on (listening
/// & cloze are speech-checkable; meaning stays think-then-reveal).
struct CardFaceTests {

    private func phraseItem(_ type: AnnotationType, text: String, context: String) -> ReviewItem {
        .annotation(Annotation(type: type, text: text,
                               contextSentence: context, languageCode: "fr-FR"))
    }

    @Test func wordAndGrammarShowMeaning() {
        #expect(phraseItem(.word, text: "chat", context: "Le chat dort.").face == .meaning)
        #expect(phraseItem(.grammar, text: "subjonctif",
                           context: "Il faut que tu viennes.").face == .meaning)
    }

    @Test func sentenceAnnotationIsListening() {
        let item = phraseItem(.sentence, text: "Le chat dort.", context: "Le chat dort.")
        #expect(item.face == .listening)
    }

    @Test func blankablePhraseIsCloze() {
        // The term appears verbatim in its context, so it can be blanked out.
        let item = phraseItem(.phrase, text: "au revoir",
                              context: "Elle a dit au revoir à ses amis.")
        #expect(item.face == .cloze)
        #expect(item.clozeText != nil)
    }

    @Test func unblankablePhraseFallsBackToMeaning() {
        // The term isn't present in the context → nothing to blank → meaning.
        let item = phraseItem(.phrase, text: "bonjour", context: "Elle a dit au revoir.")
        #expect(item.face == .meaning)
        #expect(item.clozeText == nil)
    }

    @Test func bookmarkedSentenceIsListening() {
        let sentence = Sentence(text: "Je t'aime.", orderIndex: 0)
        #expect(ReviewItem.sentence(sentence).face == .listening)
    }
}
