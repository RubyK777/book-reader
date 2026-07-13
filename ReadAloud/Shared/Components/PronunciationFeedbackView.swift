import SwiftUI
import LearningKit

/// The warm, non-numeric result of a pronunciation check (DECISIONS #39/#60):
/// a "Nicely said" confirmation when the attempt passes, or the specific words
/// to revisit as chips — never a score. Shared by the graded review and speaking
/// practice (rule of two); the "revisit" line is the only per-caller wording.
struct PronunciationFeedbackView: View {
    let result: PronunciationResult
    var revisitPrompt = "Almost — revisit:"

    var body: some View {
        if result.passed {
            Label("Nicely said", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(Theme.verdigris)
        } else {
            VStack(spacing: DesignSystem.Spacing.sm) {
                Text(revisitPrompt)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                FlowLayout(spacing: DesignSystem.Spacing.sm) {
                    ForEach(Array(result.missedWords.enumerated()), id: \.offset) { _, word in
                        Text(word)
                            .font(.callout.weight(.medium))
                            .padding(.horizontal, DesignSystem.Spacing.sm)
                            .padding(.vertical, DesignSystem.Spacing.xs)
                            .background(Palette.soft(Theme.coral), in: Capsule())
                            .foregroundStyle(Theme.coral)
                    }
                }
            }
        }
    }
}
