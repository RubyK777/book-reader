import SwiftUI
import LearningKit

/// Interactive speaking practice (PIVOT §7 pronunciation-compare): read the
/// sentence aloud, tap the mic, and the app recognizes your speech on-device and
/// checks it against the target — pass if it's close, or see which words to
/// revisit. No more silently "thinking the answer"; you actually say it. Hearing
/// the model + Slow stay available. No SRS writes — rehearsal, not testing.
struct SpeakingPracticeView: View {
    let items: [ReviewItem]

    @State private var player = SpeechPlayer()
    @State private var recorder = VoiceRecorder()
    @State private var phase: Phase = .idle
    @State private var result: PronunciationResult?
    @State private var micDenied = false
    @State private var checkUnavailable = false
    @State private var modelProgress: Double?    // non-nil while the model downloads

    private let transcriber: any Transcribing = TranscriberFactory.make()

    private enum Phase { case idle, recording, checking, done }

    var body: some View {
        PracticeSession(
            items: items,
            title: "Speaking",
            doneSystemImage: "waveform",
            doneTitle: "Well spoken",
            onLeaveCard: { resetAttempt() },
            belowHero: { item in feedback(item) },
            aboveNext: { item in controls(item) })
    }

    // MARK: Feedback (below the hero)

    @ViewBuilder
    private func feedback(_ item: ReviewItem) -> some View {
        Group {
            if let result {
                PronunciationFeedbackView(result: result,
                                          revisitPrompt: "Give it another go — revisit:")
            } else if modelProgress == nil && checkUnavailable {
                Text("Pronunciation check needs the \(LanguageCatalog.name(for: item.languageCode)) voice model — a one-time download.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if micDenied {
                Text("Microphone access is off — you can still read aloud and hear the model. Enable it in Settings to check your pronunciation.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Read it aloud, then tap the mic — I'll check how you did.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, DesignSystem.Spacing.screenMargin)
    }

    // MARK: Controls (above Next)

    @ViewBuilder
    private func controls(_ item: ReviewItem) -> some View {
        if let progress = modelProgress {
            ProgressView(value: progress) {
                Text("Downloading \(LanguageCatalog.name(for: item.languageCode)) model…")
                    .font(.subheadline)
            }
            .progressViewStyle(.linear)
            .padding(.horizontal, DesignSystem.Spacing.screenMargin)
            .frame(minHeight: DesignSystem.minTapTarget)
        } else if checkUnavailable {
            Button {
                downloadModel(item)
            } label: {
                Label("Download model", systemImage: "arrow.down.circle")
                    .frame(minHeight: DesignSystem.minTapTarget)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        } else if phase == .checking {
            HStack(spacing: DesignSystem.Spacing.sm) {
                ProgressView().controlSize(.small)
                Text("Checking…").foregroundStyle(.secondary)
            }
            .frame(minHeight: DesignSystem.minTapTarget)
        } else {
            HStack(spacing: DesignSystem.Spacing.md) {
                if !micDenied {
                    Button {
                        phase == .recording ? stopAttempt(item) : startAttempt(item)
                    } label: {
                        Label(phase == .recording ? "Stop" : "Say it",
                              systemImage: phase == .recording ? "stop.circle.fill" : "mic.fill")
                            .frame(minHeight: DesignSystem.minTapTarget)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(phase == .recording ? .red : Theme.accent)
                }

                Button {
                    player.speakLine(item.promptText, languageCode: item.languageCode)
                } label: {
                    Label("Hear it", systemImage: "speaker.wave.2.fill")
                        .frame(minHeight: DesignSystem.minTapTarget)
                }
                .buttonStyle(.bordered)

                Button {
                    player.speakLine(item.promptText, languageCode: item.languageCode, slow: true)
                } label: {
                    Label("Slow", systemImage: "tortoise.fill")
                        .frame(minHeight: DesignSystem.minTapTarget)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: Attempt

    private func startAttempt(_ item: ReviewItem) {
        player.stop()
        Task { @MainActor in
            guard await recorder.requestPermission() else {
                micDenied = true
                return
            }
            result = nil
            checkUnavailable = false
            recorder.startRecording()
            phase = .recording
        }
    }

    private func stopAttempt(_ item: ReviewItem) {
        recorder.stopRecording()
        phase = .checking
        Task { @MainActor in
            guard let url = recorder.takeFileURL,
                  await transcriber.isModelInstalled(item.languageCode) else {
                checkUnavailable = recorder.takeFileURL != nil
                phase = .idle
                return
            }
            do {
                let transcript = try await transcriber.transcribe(
                    fileURL: url, localeIdentifier: item.languageCode)
                let scored = PronunciationScorer.score(target: item.promptText, heard: transcript.text)
                result = scored
                phase = .done
                scored.passed ? Haptics.success() : Haptics.select()
            } catch {
                phase = .idle
            }
        }
    }

    private func downloadModel(_ item: ReviewItem) {
        modelProgress = 0
        Task { @MainActor in
            do {
                try await transcriber.installModel(
                    item.languageCode,
                    onProgress: { value in Task { @MainActor in modelProgress = value } })
                modelProgress = nil
                checkUnavailable = false     // model's here now — "Say it" works
            } catch {
                modelProgress = nil          // leave the offer up to retry
            }
        }
    }

    private func resetAttempt() {
        player.stop()
        recorder.reset()
        phase = .idle
        result = nil
        checkUnavailable = false
        modelProgress = nil
    }
}
