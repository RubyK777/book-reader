import Foundation
import Speech
import AVFoundation
import CoreMedia

/// iOS 26 `SpeechAnalyzer`/`SpeechTranscriber` engine: robust on-device
/// transcription with native per-word timings, and on-demand model download
/// (system-managed — audio never leaves the device; only the model is fetched,
/// once, with the user's consent). Falls back to `OnDeviceTranscriber` on older
/// iOS via `TranscriberFactory`.
@available(iOS 26, *)
struct SpeechAnalyzerTranscriber: Transcribing {
    func isSupported(_ localeIdentifier: String) async -> Bool {
        await matchedLocale(localeIdentifier) != nil
    }

    func isModelInstalled(_ localeIdentifier: String) async -> Bool {
        guard let matched = await matchedLocale(localeIdentifier) else { return false }
        let installed = await SpeechTranscriber.installedLocales
        return installed.contains { $0.identifier(.bcp47) == matched.identifier(.bcp47) }
    }

    func installModel(_ localeIdentifier: String,
                      onProgress: @escaping @Sendable (Double) -> Void) async throws {
        guard let matched = await matchedLocale(localeIdentifier) else {
            throw TranscriptionError.unavailableForLanguage
        }
        let transcriber = makeTranscriber(locale: matched)
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
            onProgress(1)   // nothing to fetch — already satisfied
            return
        }
        // Report the system download's fractionCompleted while it installs; the
        // poller is torn down as soon as downloadAndInstall() returns.
        let progress = request.progress
        let poller = Task {
            while !Task.isCancelled {
                onProgress(progress.fractionCompleted)
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        defer { poller.cancel() }
        try await request.downloadAndInstall()
        onProgress(1)
    }

    func transcribe(fileURL: URL, localeIdentifier: String,
                    onProgress: @escaping @Sendable (Double) -> Void) async throws -> Transcript {
        guard let matched = await matchedLocale(localeIdentifier) else {
            throw TranscriptionError.unavailableForLanguage
        }
        let transcriber = makeTranscriber(locale: matched)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let audioFile = try AVAudioFile(forReading: fileURL)
        let totalSeconds = Double(audioFile.length) / audioFile.processingFormat.sampleRate

        // Collect results concurrently while the analyzer consumes the file,
        // reporting progress from how far into the clip we've transcribed.
        let collector = Task { () throws -> (String, [TranscriptSegment]) in
            var full = AttributedString()
            var segments: [TranscriptSegment] = []
            for try await result in transcriber.results {
                full.append(result.text)
                for run in result.text.runs {
                    guard let range = run.audioTimeRange else { continue }
                    let word = String(result.text[run.range].characters)
                    segments.append(TranscriptSegment(
                        text: word,
                        start: range.start.seconds,
                        duration: range.duration.seconds))
                    if totalSeconds > 0 {
                        onProgress(min(1, range.end.seconds / totalSeconds))
                    }
                }
            }
            return (String(full.characters), segments)
        }

        if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
        }

        let (text, segments) = try await collector.value
        onProgress(1)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranscriptionError.noSpeechFound
        }
        return Transcript(text: text, segments: segments, detectedLocale: matched.identifier(.bcp47))
    }

    private func makeTranscriber(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(locale: locale,
                          transcriptionOptions: [],
                          reportingOptions: [],
                          attributeOptions: [.audioTimeRange])
    }

    private func matchedLocale(_ localeIdentifier: String) async -> Locale? {
        await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: localeIdentifier))
    }
}
