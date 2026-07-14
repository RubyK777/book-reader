import Testing
import Foundation
@testable import ReadAloud

/// `SRSState.review` integration. The SM-2 scheduling math itself is unit-tested
/// purely in `LearningKit.SM2SchedulerTests`; these tests verify the app-side
/// wiring — that `SRSState` maps its embedded fields through the scheduler and
/// derives `dueDate` from the resulting interval.
struct SRSStateTests {

    /// True if `date` is ~`days` ahead of now, tolerant of the millisecond gap
    /// between `review()` capturing `.now` and this check reading it.
    private func isDaysAhead(_ date: Date, _ days: Int) -> Bool {
        abs(date.timeIntervalSinceNow - Double(days) * 86_400) < 120
    }

    @Test func freshCardGradedGoodSchedulesOneDayOut() {
        var s = SRSState()   // repetitions 0, ease 2.5, interval 0
        s.review(quality: 4) // Good
        #expect(s.repetitions == 1)
        #expect(s.intervalDays == 1)
        #expect(abs(s.easeFactor - 2.5) < 0.0001)
        #expect(isDaysAhead(s.dueDate, 1))
    }

    @Test func twoGoodReviewsDelegateThroughScheduler() {
        var s = SRSState()
        s.review(quality: 4)
        #expect(s.intervalDays == 1)
        s.review(quality: 4)
        #expect(s.repetitions == 2)
        #expect(s.intervalDays == 6)
        #expect(isDaysAhead(s.dueDate, 6))
    }

    @Test func lapseResetsAndReschedulesTomorrow() {
        var s = SRSState()
        s.review(quality: 4)
        s.review(quality: 4) // rep 2, interval 6
        s.review(quality: 1) // Again
        #expect(s.repetitions == 0)
        #expect(s.intervalDays == 1)
        #expect(isDaysAhead(s.dueDate, 1))
    }
}
