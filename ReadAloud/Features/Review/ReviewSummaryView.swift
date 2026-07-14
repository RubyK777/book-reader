import SwiftUI

/// The end-of-session screen: a seal, the count reviewed, a per-grade tally, and
/// the follow-on actions (ungraded shadowing practice, review more, or done).
struct ReviewSummaryView: View {
    let tally: [ReviewGrade: Int]
    let shadowableCount: Int
    let remainingDue: Int
    /// The next due date, resolved by the caller — shown only when nothing is
    /// left to review now.
    let nextDueDate: Date?
    let onPracticeSpeaking: () -> Void
    let onReviewMore: () -> Void
    let onDone: () -> Void

    var body: some View {
        let total = tally.values.reduce(0, +)
        return VStack(spacing: DesignSystem.Spacing.lg) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: DesignSystem.IconSize.xl))
                .foregroundStyle(Theme.verdigris)
                .symbolEffect(.bounce)

            VStack(spacing: DesignSystem.Spacing.xs) {
                Text("Session complete")
                    .font(.title2.bold())
                Text(total == 1 ? "You reviewed 1 card" : "You reviewed \(total) cards")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: DesignSystem.Spacing.sm) {
                ForEach(Array(ReviewGrade.allCases.enumerated()), id: \.element) { index, grade in
                    HStack {
                        Circle()
                            .fill(grade.tint)
                            .frame(width: 8, height: 8)
                        Text(grade.label)
                        Spacer()
                        CountUpText(value: tally[grade] ?? 0,
                                    delay: 0.15 * Double(index),
                                    font: .body.monospacedDigit())
                    }
                }
            }
            .padding(DesignSystem.Spacing.md)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
            .padding(.horizontal, DesignSystem.Spacing.screenMargin)

            Spacer()

            VStack(spacing: DesignSystem.Spacing.sm) {
                // Ungraded shadowing practice on the session's full sentences
                // (product design Phase 3 — never interrupts the graded flow).
                if shadowableCount > 0 {
                    Button {
                        onPracticeSpeaking()
                    } label: {
                        Label("Practice speaking (\(shadowableCount))",
                              systemImage: "mic")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                if remainingDue > 0 {
                    Button {
                        onReviewMore()
                    } label: {
                        Text("Review \(remainingDue) more")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else if let nextDueDate {
                    Text("Next review \(nextDueDate.relativeNamed)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if remainingDue > 0 {
                    Button { onDone() } label: {
                        Text("Done").font(.headline).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                } else {
                    Button { onDone() } label: {
                        Text("Done").font(.headline).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.screenMargin)
            .padding(.bottom, DesignSystem.Spacing.lg)
        }
    }
}
