import SwiftUI

/// The list of annotations saved from a sentence (shown inside the Learn view's
/// "Saved from this sentence" card). Pure presentation over a pre-sorted list.
struct SentenceSavedItemsList: View {
    /// Annotations, already sorted by the caller (oldest first).
    let annotations: [Annotation]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            ForEach(annotations) { annotation in
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Text(annotation.type.rawValue)
                        .font(.caption2.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(DesignSystem.accent)
                    Text(annotation.text)
                        .font(.callout)
                    if let intent = annotation.intent {
                        Text(intent.displayName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}
