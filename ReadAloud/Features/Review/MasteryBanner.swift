import SwiftUI

/// The "taking root" moment banner — a leaf, a warm line, gone in a beat.
/// Shown briefly the first time a card reaches memory maturity (DECISIONS #39:
/// a tasteful growth marker, never a streak or score).
struct MasteryBanner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "leaf.fill")
                .foregroundStyle(Theme.verdigris)
            VStack(alignment: .leading, spacing: 2) {
                Text("Taking root")
                    .font(.subheadline.weight(.semibold))
                Text("You've really learned this.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Theme.verdigris.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        .padding(.top, DesignSystem.Spacing.sm)
        .transition(reduceMotion ? .opacity
                    : .move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Taking root. You've really learned this.")
    }
}
