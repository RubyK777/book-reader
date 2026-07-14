import Foundation

/// SM-2 spaced-repetition scheduling — the deterministic math the Review flow
/// depends on. Extracted from the app's `SRSState` so it can be unit-tested in
/// isolation (DECISIONS #68 deferred this extraction; this completes it).
///
/// The engine is **pure**: given a card's SM-2 fields and a review quality it
/// returns the updated fields, and it knows nothing about dates or persistence.
/// The caller stores the fields and turns `intervalDays` into a due date — that
/// (impure, `Calendar`-bound) step stays in the app.
public enum SM2Scheduler {

    /// The schedulable state of one card: the three SM-2 fields the algorithm
    /// reads and writes. Defaults match a brand-new card.
    public struct Card: Equatable {
        /// Number of consecutive successful reviews (reset to 0 on a lapse).
        public var repetitions: Int
        /// Ease multiplier; never falls below ``minimumEaseFactor``.
        public var easeFactor: Double
        /// Days until the card is next due.
        public var intervalDays: Int

        public init(repetitions: Int = 0,
                    easeFactor: Double = 2.5,
                    intervalDays: Int = 0) {
            self.repetitions = repetitions
            self.easeFactor = easeFactor
            self.intervalDays = intervalDays
        }
    }

    /// The lowest an ease factor may fall (classic SM-2 floor).
    public static let minimumEaseFactor = 1.3

    /// Apply one graded review and return the updated card (the input is not
    /// mutated).
    ///
    /// `quality` runs 0 (total blackout) … 5 (perfect recall). Anything below 3
    /// is a lapse: repetitions reset and the card is due again in one day. The
    /// ease factor is always adjusted by the SM-2 formula and clamped to
    /// ``minimumEaseFactor``.
    public static func review(_ card: Card, quality: Int) -> Card {
        var next = card
        if quality < 3 {
            next.repetitions = 0
            next.intervalDays = 1
        } else {
            switch next.repetitions {
            case 0: next.intervalDays = 1
            case 1: next.intervalDays = 6
            // Uses the pre-update ease factor, matching the original SM-2 order.
            default: next.intervalDays = Int(Double(next.intervalDays) * next.easeFactor)
            }
            next.repetitions += 1
        }
        next.easeFactor = max(minimumEaseFactor, next.easeFactor + 0.1
            - Double(5 - quality) * (0.08 + Double(5 - quality) * 0.02))
        return next
    }
}
