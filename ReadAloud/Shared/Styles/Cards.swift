import SwiftUI

/// Card chrome and section headers — the shared "paper" surfaces. Moved here
/// from `Theme.swift` verbatim (pure reorganization; no call-site changes).

// MARK: - Card chrome

/// Standard content card: warm paper, hairline stroke, soft radius.
/// `active` tints it with the accent (playing sentence, selected state).
struct LearningCard: ViewModifier {
    var active = false

    func body(content: Content) -> some View {
        content
            .padding(DesignSystem.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    .fill(active ? Theme.accentSoft : Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    .strokeBorder(active ? Theme.accent : Theme.cardStroke,
                                  lineWidth: active ? 1.5 : 1)
            )
    }
}

extension View {
    func learningCard(active: Bool = false) -> some View {
        modifier(LearningCard(active: active))
    }
}

// MARK: - Section header (Learn view, detail screens)

/// Uppercase micro-label with the accent icon — one consistent section voice.
struct SectionHeaderLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
            Text(title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .kerning(0.8)
                .foregroundStyle(.secondary)
        }
    }
}
