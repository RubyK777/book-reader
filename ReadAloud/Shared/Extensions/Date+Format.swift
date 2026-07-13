import Foundation

extension Date {
    /// Named relative style ("tomorrow", "in 3 days") — the app's standard
    /// phrasing for due/next-review dates.
    var relativeNamed: String {
        formatted(.relative(presentation: .named))
    }

    /// Compact absolute date ("Jul 12, 2026") for saved-item captions.
    var shortDate: String {
        formatted(.dateTime.month().day().year())
    }
}
