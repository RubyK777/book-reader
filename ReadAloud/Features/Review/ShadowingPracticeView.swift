import SwiftUI

/// Ungraded shadowing practice (PIVOT_PLAN Phase 3, D4): play the original,
/// record yourself, replay both, move on. No SRS writes — this is rehearsal,
/// not testing. Mic denial hides recording but never blocks listening. Built on
/// the shared `PracticeSession` scaffold; the record controls are its distinct part.
struct ShadowingPracticeView: View {
    let items: [ReviewItem]

    @State private var player = SpeechPlayer()
    @State private var recorder = VoiceRecorder()
    @State private var micDenied = false

    var body: some View {
        PracticeSession(
            items: items,
            title: "Shadowing",
            doneSystemImage: "mic.badge.plus",
            doneTitle: "Well practiced",
            onLeaveCard: { player.stop(); recorder.reset() },
            belowHero: { item in
                HStack(spacing: DesignSystem.Spacing.md) {
                    Button {
                        recorder.stopPlayback()
                        player.speakLine(item.promptText, languageCode: item.languageCode)
                    } label: {
                        Label("Original", systemImage: "speaker.wave.2.fill")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        recorder.stopPlayback()
                        player.speakLine(item.promptText, languageCode: item.languageCode, slow: true)
                    } label: {
                        Label("Slow", systemImage: "tortoise.fill")
                    }
                    .buttonStyle(.bordered)
                }
            },
            aboveNext: { _ in recordSection })
    }

    @ViewBuilder
    private var recordSection: some View {
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
}
