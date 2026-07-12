import SwiftUI

/// First-run teaching cards (≤3 panels), shown once when the Library is empty
/// on first launch. Strictly instructional — no rewards, streaks, or scores
/// (DECISIONS #39). Built entirely from `AnimatedEmptyState` so it speaks the
/// app's existing visual language; a `TabView(.page)` swipes between panels.
/// Gated by the caller on `@AppStorage("hasSeenIntro")`.
struct WelcomeView: View {
    /// Called when the learner finishes or skips. `startScan` is true only when
    /// they tapped "Scan your first page" on the last panel; the caller marks
    /// the intro seen and, if asked, opens the scan flow.
    let onFinish: (_ startScan: Bool) -> Void

    @AppStorage("nativeLanguage") private var nativeLanguage = LanguageCatalog.deviceDefaultNative
    @State private var page = 0

    /// The native language is still the device default — worth a gentle,
    /// bilingual-aware nudge that it's changeable (never assumes English).
    private var isNativeDefault: Bool {
        nativeLanguage == LanguageCatalog.deviceDefaultNative
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip") { onFinish(false) }
                    .font(.subheadline)
                    .padding(DesignSystem.Spacing.md)
            }

            TabView(selection: $page) {
                panelOne.tag(0)
                panelTwo.tag(1)
                panelThree.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
    }

    private var panelOne: some View {
        AnimatedEmptyState(
            title: "Photograph any text",
            message: "A book page, a street sign, a menu — capture the words you want to understand.",
            systemImage: "camera.viewfinder",
            tint: Theme.coral)
    }

    private var panelTwo: some View {
        AnimatedEmptyState(
            title: "Listen, word by word",
            message: "Hear it read aloud in a natural voice, each word lighting up as it's spoken.",
            systemImage: "waveform",
            tint: Theme.accent)
    }

    private var panelThree: some View {
        AnimatedEmptyState(
            title: "Keep what's worth learning",
            message: "Save a word or sentence and it comes back to review, spaced out over time — right when you need it.",
            systemImage: "bookmark",
            tint: Theme.violet) {
            VStack(spacing: DesignSystem.Spacing.md) {
                Button { onFinish(true) } label: {
                    Label("Scan your first page", systemImage: "camera")
                }
                .buttonStyle(SpringyProminentButtonStyle(tint: Theme.violet))

                if isNativeDefault {
                    Text("Reading into \(LanguageCatalog.name(for: nativeLanguage))? You can change your language any time in Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.xl)
        }
    }
}

#Preview {
    WelcomeView { _ in }
}
