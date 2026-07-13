import SwiftUI

/// Ungraded speaking practice (docs/IMPROVEMENTS §01 production face): read each
/// item aloud straight from the text — a *cold* read — then tap to hear the
/// model and self-check. No recording, no SRS writes. Distinct from Shadowing,
/// which plays the model first; here the text leads and the audio is the answer.
/// Built on the shared `PracticeSession` scaffold.
struct SpeakingPracticeView: View {
    let items: [ReviewItem]

    @State private var player = SpeechPlayer()

    var body: some View {
        PracticeSession(
            items: items,
            title: "Speaking",
            doneSystemImage: "waveform",
            doneTitle: "Well spoken",
            onLeaveCard: { player.stop() },
            belowHero: { _ in
                Text("Read it aloud, then hear how it should sound.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DesignSystem.Spacing.screenMargin)
            },
            aboveNext: { item in
                HStack(spacing: DesignSystem.Spacing.md) {
                    Button {
                        player.speakLine(item.promptText, languageCode: item.languageCode)
                    } label: {
                        Label("Hear it", systemImage: "speaker.wave.2.fill")
                            .frame(minHeight: DesignSystem.minTapTarget)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        player.speakLine(item.promptText, languageCode: item.languageCode, slow: true)
                    } label: {
                        Label("Slow", systemImage: "tortoise.fill")
                            .frame(minHeight: DesignSystem.minTapTarget)
                    }
                    .buttonStyle(.bordered)
                }
            })
    }
}
