import SwiftUI

/// The shared empty/placeholder state for the content tabs — a tinted,
/// breathing SF Symbol over a soft mesh disc, a title/message, and an optional
/// `actions` slot. Replaces bare `ContentUnavailableView` so every tab's empty
/// state has the same energetic-but-calm voice. Reduce Motion stills the
/// breathing (the mesh disc is already static).
struct AnimatedEmptyState<Actions: View>: View {
    let title: String
    let message: String
    let systemImage: String
    var tint: Color = Theme.accent
    @ViewBuilder var actions: () -> Actions

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    init(title: String,
         message: String,
         systemImage: String,
         tint: Color = Theme.accent,
         @ViewBuilder actions: @escaping () -> Actions = { EmptyView() }) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.tint = tint
        self.actions = actions
    }

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Spacer()

            ZStack {
                AnimatedMeshBackground(isStatic: true)
                    .frame(width: 128, height: 128)
                    .clipShape(Circle())
                    .opacity(0.7)
                Circle()
                    .fill(Palette.soft(tint))
                    .frame(width: 96, height: 96)
                icon
            }
            .accessibilityHidden(true)

            VStack(spacing: DesignSystem.Spacing.sm) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, DesignSystem.Spacing.xl)

            actions()

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var icon: some View {
        if reduceMotion {
            Image(systemName: systemImage)
                .font(.system(size: DesignSystem.IconSize.hero))
                .foregroundStyle(tint)
        } else {
            // Custom breathing instead of `.symbolEffect(.breathe)` — that effect's
            // scale pulse reads as too strong and its amplitude isn't adjustable.
            // A small, slow scale (±3%) with a soft opacity fade is a gentle,
            // still-visible breath.
            Image(systemName: systemImage)
                .font(.system(size: DesignSystem.IconSize.hero))
                .foregroundStyle(tint)
                .scaleEffect(breathing ? 1.03 : 0.97)
                .opacity(breathing ? 1.0 : 0.85)
                .animation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true),
                           value: breathing)
                .onAppear { breathing = true }
        }
    }
}
