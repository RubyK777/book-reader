import SwiftUI

/// Ungraded speaking practice (docs/IMPROVEMENTS §01 production face): read each
/// item aloud straight from the text — a *cold* read — then tap to hear the
/// model and self-check your pronunciation. No recording, no SRS writes. Distinct
/// from Shadowing, which plays the model first; here the text leads and the
/// audio is the answer. Reuses `SpeechPlayer.speakOnce`.
struct SpeakingPracticeView: View {
    let items: [ReviewItem]

    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var player = SpeechPlayer()

    private var current: ReviewItem? {
        items.indices.contains(index) ? items[index] : nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if let item = current {
                    practiceView(item)
                } else {
                    doneView
                }
            }
            .navigationTitle("Speaking")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { close() }
                }
            }
        }
        .onDisappear { player.stop() }
    }

    @ViewBuilder
    private func practiceView(_ item: ReviewItem) -> some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Text("\(index + 1) of \(items.count)")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)

            Spacer()

            Text(item.promptText)
                .font(Theme.heroFont)
                .fontDesign(Theme.sentenceDesign)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .learningCard()
                .padding(.horizontal, DesignSystem.Spacing.md)

            Text("Read it aloud, then hear how it should sound.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DesignSystem.Spacing.screenMargin)

            Spacer()

            HStack(spacing: DesignSystem.Spacing.md) {
                Button {
                    play(item)
                } label: {
                    Label("Hear it", systemImage: "speaker.wave.2.fill")
                        .frame(minHeight: DesignSystem.minTapTarget)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    player.load(sentences: [item.promptText], languageCode: item.languageCode)
                    player.speakOnce(item.promptText, slow: true)
                } label: {
                    Label("Slow", systemImage: "tortoise.fill")
                        .frame(minHeight: DesignSystem.minTapTarget)
                }
                .buttonStyle(.bordered)
            }

            Button {
                advance()
            } label: {
                Text(index + 1 < items.count ? "Next" : "Finish")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .padding(.horizontal, DesignSystem.Spacing.screenMargin)
        }
        .padding(DesignSystem.Spacing.lg)
    }

    private var doneView: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: "waveform")
                .font(.system(size: DesignSystem.IconSize.hero))
                .foregroundStyle(DesignSystem.accent)
            Text("Well spoken")
                .font(.title3.bold())
            Button { close() } label: {
                Text("Done").font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, DesignSystem.Spacing.screenMargin)
        }
        .padding(DesignSystem.Spacing.lg)
    }

    private func play(_ item: ReviewItem) {
        player.load(sentences: [item.promptText], languageCode: item.languageCode)
        player.play(at: 0)
    }

    private func advance() {
        player.stop()
        if index + 1 < items.count {
            index += 1
        } else {
            index = items.count   // → doneView
        }
    }

    private func close() {
        player.stop()
        dismiss()
    }
}
