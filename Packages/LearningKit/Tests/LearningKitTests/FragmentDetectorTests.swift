import Testing
import LearningKit

/// UX_SPEC §8: fragments (signs, menu lines, prices) are phrase-type units.
struct FragmentDetectorTests {

    @Test func menuLineWithPriceIsFragment() {
        #expect(FragmentDetector.isFragment("Salade niçoise — 14€"))
    }

    @Test func bareLabelIsFragment() {
        #expect(FragmentDetector.isFragment("Sortie"))
        #expect(FragmentDetector.isFragment("Poussez"))
    }

    @Test func priceOnlyIsFragment() {
        #expect(FragmentDetector.isFragment("18€"))
        #expect(FragmentDetector.isFragment("9h – 18h"))
    }

    @Test func terminatedSentenceIsNotFragment() {
        #expect(!FragmentDetector.isFragment("Je n'arrive pas à y croire."))
        #expect(!FragmentDetector.isFragment("Il faut que tu viennes demain !"))
    }

    @Test func longUnterminatedSignIsNotFragment() {
        // 6+ words carry real structure worth a grammar point,
        // e.g. "défense de + infinitive".
        #expect(!FragmentDetector.isFragment("Défense de stationner devant la porte"))
    }

    @Test func shortUnterminatedPhraseIsFragment() {
        #expect(FragmentDetector.isFragment("Fermé le lundi"))
    }

    @Test func emptyAndWhitespaceAreNotFragments() {
        #expect(!FragmentDetector.isFragment(""))
        #expect(!FragmentDetector.isFragment("   "))
    }
}
