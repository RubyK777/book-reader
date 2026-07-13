import Testing
import LearningKit

/// D5: cloze blanks are deterministic — the saved term is the blank.
struct ClozeBuilderTests {

  @Test func blanksPhraseInsideSentence() {
    let cloze = ClozeBuilder.blank(
      term: "arrive pas", in: "Je n'arrive pas à y croire.")
    #expect(cloze == "Je n'\(ClozeBuilder.mask) à y croire.")
  }

  @Test func matchIsCaseAndDiacriticInsensitive() {
    let cloze = ClozeBuilder.blank(
      term: "defense de", in: "Défense de stationner devant la porte")
    #expect(cloze == "\(ClozeBuilder.mask) stationner devant la porte")
  }

  @Test func termNotInSentenceReturnsNil() {
    #expect(ClozeBuilder.blank(term: "bonjour", in: "Je suis là.") == nil)
  }

  @Test func wholeSentenceTermReturnsNil() {
    // Blanking everything leaves no card — fall back to a meaning face.
    #expect(ClozeBuilder.blank(term: "Fermé le lundi", in: "Fermé le lundi") == nil)
    #expect(ClozeBuilder.blank(term: "fermé le lundi ", in: " Fermé le lundi") == nil)
  }

  @Test func emptyInputsReturnNil() {
    #expect(ClozeBuilder.blank(term: "", in: "Je suis là.") == nil)
    #expect(ClozeBuilder.blank(term: "là", in: "") == nil)
  }
}
