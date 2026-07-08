import Testing
import Foundation
@testable import ReadAloud

/// SM-2 scheduling math (`SRSState.review`). These are the exact expected
/// values the Review flow depends on — a change here changes every user's
/// schedule, so pin them.
struct SRSStateTests {

    /// True if `date` is ~`days` ahead of now, tolerant of the millisecond gap
    /// between `review()` capturing `.now` and this check reading it.
    private func isDaysAhead(_ date: Date, _ days: Int) -> Bool {
        abs(date.timeIntervalSinceNow - Double(days) * 86_400) < 120
    }

    @Test func freshCardGradedGood() {
        var s = SRSState()   // repetitions 0, ease 2.5, interval 0
        s.review(quality: 4) // Good
        #expect(s.repetitions == 1)
        #expect(s.intervalDays == 1)
        #expect(abs(s.easeFactor - 2.5) < 0.0001)
        #expect(isDaysAhead(s.dueDate, 1))
    }

    @Test func twoGoodReviewsGiveOneThenSixDays() {
        var s = SRSState()
        s.review(quality: 4)
        #expect(s.intervalDays == 1)
        s.review(quality: 4)
        #expect(s.repetitions == 2)
        #expect(s.intervalDays == 6)
    }

    @Test func thirdGoodMultipliesByEase() {
        var s = SRSState()
        s.review(quality: 4) // -> interval 1, rep 1
        s.review(quality: 4) // -> interval 6, rep 2
        s.review(quality: 4) // -> interval 6 * 2.5 = 15, rep 3
        #expect(s.repetitions == 3)
        #expect(s.intervalDays == 15)
    }

    @Test func againResetsRepetitionsAndInterval() {
        var s = SRSState()
        s.review(quality: 4)
        s.review(quality: 4) // now rep 2, interval 6
        s.review(quality: 1) // Again
        #expect(s.repetitions == 0)
        #expect(s.intervalDays == 1)
        #expect(isDaysAhead(s.dueDate, 1))
    }

    @Test func easyRaisesEaseFactor() {
        var s = SRSState()
        s.review(quality: 5) // Easy: ease += 0.1
        #expect(abs(s.easeFactor - 2.6) < 0.0001)
    }

    @Test func hardLowersEaseFactor() {
        var s = SRSState()
        s.review(quality: 3) // Hard: 2.5 + 0.1 - 2*(0.08 + 2*0.02) = 2.36
        #expect(abs(s.easeFactor - 2.36) < 0.0001)
    }

    @Test func easeNeverDropsBelowFloor() {
        var s = SRSState()
        for _ in 0..<20 { s.review(quality: 1) } // repeated Again
        #expect(s.easeFactor >= 1.3)
    }
}
