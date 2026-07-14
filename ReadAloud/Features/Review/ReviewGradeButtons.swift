import SwiftUI

/// The four SM-2 grade buttons ("How well did you know it?"). When a speech
/// check ran, `suggestedGrade` gets a thicker outline to nudge — but never
/// forces — the grade.
struct ReviewGradeButtons: View {
    let suggestedGrade: ReviewGrade?
    let onGrade: (ReviewGrade) -> Void

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Text("How well did you know it?")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(spacing: DesignSystem.Spacing.xs) {
                ForEach(ReviewGrade.allCases) { grade in
                    Button {
                        onGrade(grade)
                    } label: {
                        VStack(spacing: 2) {
                            Text(grade.label)
                                .font(.callout.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(grade.hint)
                                .font(.caption2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .opacity(0.9)
                        }
                        .frame(maxWidth: .infinity, minHeight: DesignSystem.minTapTarget)
                        .padding(.vertical, DesignSystem.Spacing.sm)
                        .background(grade.tint.opacity(0.15),
                                    in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                        .overlay(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                            .stroke(grade.tint, lineWidth: grade == suggestedGrade ? 3 : 1))
                        .foregroundStyle(grade.tint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(grade.label), \(grade.hint)")
                }
            }
        }
    }
}
