import SwiftUI

/// Ungraded shadowing practice (PIVOT_PLAN Phase 3, D4): play the original,
/// record yourself, replay both, move on. No SRS writes — this is rehearsal,
/// not testing. Mic denial hides recording but never blocks listening.
struct ShadowingPracticeView: View {
    let items: [ReviewItem]

    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var player = SpeechPlayer()
    @State private var recorder = VoiceRecorder()
    @State private var micDenied = false

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
            .navigationTitle("Shadowing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { close() }
                }
            }
        }
        .onDisappear {
            player.stop()
            recorder.reset()
        }
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

            HStack(spacing: DesignSystem.Spacing.md) {
                Button {
                    recorder.stopPlayback()
                    player.load(sentences: [item.promptText], languageCode: item.languageCode)
                    player.play(at: 0)
                } label: {
                    Label("Original", systemImage: "speaker.wave.2.fill")
                }
                .buttonStyle(.bordered)

                Button {
                    recorder.stopPlayback()
                    player.load(sentences: [item.promptText], languageCode: item.languageCode)
                    player.speakOnce(item.promptText, slow: true)
                } label: {
                    Label("Slow", systemImage: "tortoise.fill")
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            if micDenied {
                Text("Microphone access is off — you can still listen and repeat aloud. Enable it in Settings to record and compare.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DesignSystem.Spacing.screenMargin)
            } else {
                VStack(spacing: DesignSystem.Spacing.md) {
                    Button {
                        toggleRecording()
                    } label: {
                        Label(recorder.state == .recording ? "Stop" : "Record",
                              systemImage: recorder.state == .recording ? "stop.circle.fill" : "mic.fill")
                            .font(.headline)
                            .frame(maxWidth: 220)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(recorder.state == .recording ? .red : Theme.accent)

                    Button {
                        recorder.playTake()
                    } label: {
                        Label("Play my take", systemImage: "person.wave.2.fill")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!recorder.hasTake || recorder.state == .recording)
                }
            }

            Button {
                advance()
            } label: {
                Text(index + 1 < items.count ? "Next sentence" : "Finish")
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
            Image(systemName: "mic.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(DesignSystem.accent)
            Text("Nice practice!")
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

    private func toggleRecording() {
        if recorder.state == .recording {
            recorder.stopRecording()
            Haptics.select()
            return
        }
        player.stop()
        Task {
            guard await recorder.requestPermission() else {
                micDenied = true
                return
            }
            recorder.startRecording()
            Haptics.select()
        }
    }

    private func advance() {
        player.stop()
        recorder.reset()
        if index + 1 < items.count {
            index += 1
        } else {
            index = items.count   // → doneView
        }
    }

    private func close() {
        player.stop()
        recorder.reset()
        dismiss()
    }
}
