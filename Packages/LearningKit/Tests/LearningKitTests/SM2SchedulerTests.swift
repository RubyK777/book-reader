import Testing
@testable import LearningKit

/// SM-2 scheduling math (`SM2Scheduler.review`). These are the exact expected
/// values the Review flow depends on — a change here changes every learner's
/// schedule, so pin them. Pure (no dates); the app's `SRSState` derives the due
/// date from `intervalDays` separately.
struct SM2SchedulerTests {

    @Test func freshCardGradedGood() {
        let c = SM2Scheduler.review(.init(), quality: 4) // Good on a new card
        #expect(c.repetitions == 1)
        #expect(c.intervalDays == 1)
        #expect(abs(c.easeFactor - 2.5) < 0.0001)
    }

    @Test func twoGoodReviewsGiveOneThenSixDays() {
        var c = SM2Scheduler.review(.init(), quality: 4)
        #expect(c.intervalDays == 1)
        c = SM2Scheduler.review(c, quality: 4)
        #expect(c.repetitions == 2)
        #expect(c.intervalDays == 6)
    }

    @Test func thirdGoodMultipliesByEase() {
        var c = SM2Scheduler.review(.init(), quality: 4) // interval 1, rep 1
        c = SM2Scheduler.review(c, quality: 4)           // interval 6, rep 2
        c = SM2Scheduler.review(c, quality: 4)           // 6 * 2.5 = 15, rep 3
        #expect(c.repetitions == 3)
        #expect(c.intervalDays == 15)
    }

    @Test func againResetsRepetitionsAndInterval() {
        var c = SM2Scheduler.review(.init(), quality: 4)
        c = SM2Scheduler.review(c, quality: 4) // rep 2, interval 6
        c = SM2Scheduler.review(c, quality: 1) // Again
        #expect(c.repetitions == 0)
        #expect(c.intervalDays == 1)
    }

    @Test func easyRaisesEaseFactor() {
        let c = SM2Scheduler.review(.init(), quality: 5) // Easy: ease += 0.1
        #expect(abs(c.easeFactor - 2.6) < 0.0001)
    }

    @Test func hardLowersEaseFactor() {
        // Hard: 2.5 + 0.1 - 2*(0.08 + 2*0.02) = 2.36
        let c = SM2Scheduler.review(.init(), quality: 3)
        #expect(abs(c.easeFactor - 2.36) < 0.0001)
    }

    @Test func easeNeverDropsBelowFloor() {
        var c = SM2Scheduler.Card()
        for _ in 0..<20 { c = SM2Scheduler.review(c, quality: 1) } // repeated Again
        #expect(c.easeFactor >= SM2Scheduler.minimumEaseFactor)
    }

    @Test func reviewDoesNotMutateInput() {
        let original = SM2Scheduler.Card(repetitions: 2, easeFactor: 2.5, intervalDays: 6)
        _ = SM2Scheduler.review(original, quality: 4)
        #expect(original == SM2Scheduler.Card(repetitions: 2, easeFactor: 2.5, intervalDays: 6))
    }
}
