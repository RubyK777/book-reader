import SwiftUI

/// "3 of 12" (or "Page 3 of 12") in the app's standard caption style. Shared by
/// the review, practice, and batch-scan flows that all showed a position counter.
struct ProgressCounter: View {
    let current: Int
    let total: Int
    var noun: String?

    var body: some View {
        Text(label)
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
    }

    private var label: String {
        let prefix = noun.map { "\($0) " } ?? ""
        return "\(prefix)\(current) of \(total)"
    }
}
