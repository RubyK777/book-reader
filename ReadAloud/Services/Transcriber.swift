import Foundation
import Speech

/// One recognized token with its timing (seconds into the clip).
struct TranscriptSegment: Sendable {
    let text: String
    let start: Double
    let duration: Double
    var end: Double { start + duration }
}

/// The result of transcribing an audio clip.
struct Transcript: Sendable {
    let text: String
    let segments: [TranscriptSegment]
    let detectedLocale: String?
}

enum TranscriptionError: Error {
    case notAuthorized
    case unavailableForLanguage       // the language isn't recognized at all
    case modelNotInstalled            // recognized, but the on-device model needs downloading
    case downloadFailed
    case recognitionFailed
    case noSpeechFound
}

/// Audio → timestamped text, fully on-device/offline (AUDIO_LEARNING_DESIGN §5.1).
/// Recognition never sends audio anywhere; downloading the *model* (once, with
/// consent) is a system asset download, not user data (DECISIONS #59).
protocol Transcribing {
    /// The language is recognizable (its model may still need downloading).
    func isSupported(_ localeIdentifier: String) async -> Bool
    /// The on-device model is already present (transcription can run immediately).
    func isModelInstalled(_ localeIdentifier: String) async -> Bool
    /// Download + install the on-device model for a supported language.
    func installModel(_ localeIdentifier: String) async throws
    /// Transcribe a local audio file into timestamped text. Never leaves the
    /// device. `onProgress` reports 0…1 completion (best-effort).
    func transcribe(fileURL: URL, localeIdentifier: String,
                    onProgress: @escaping @Sendable (Double) -> Void) async throws -> Transcript
}

extension Transcribing {
    func transcribe(fileURL: URL, localeIdentifier: String) async throws -> Transcript {
        try await transcribe(fileURL: fileURL, localeIdentifier: localeIdentifier, onProgress: { _ in })
    }
}

/// Picks the best available engine: iOS 26 `SpeechAnalyzer` (on-demand model
/// download + word timings) when present, else the `SFSpeechRecognizer` baseline.
enum TranscriberFactory {
    static func make() -> any Transcribing {
        if #available(iOS 26, *) {
            return SpeechAnalyzerTranscriber()
        }
        return OnDeviceTranscriber()
    }
}

/// `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true` — audio never
/// leaves the device (upholds DECISIONS #31). Whole-file recognition for the MVP;
/// long-clip windowed chunking is a documented enhancement (§9).
struct OnDeviceTranscriber: Transcribing {
    func isSupported(_ localeIdentifier: String) async -> Bool {
        SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)) != nil
    }

    func isModelInstalled(_ localeIdentifier: String) async -> Bool {
        SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))?.supportsOnDeviceRecognition ?? false
    }

    /// Pre-iOS 26 there's no programmatic model download — the OS installs it when
    /// the language is enabled for dictation. Surface that as a failure to install.
    func installModel(_ localeIdentifier: String) async throws {
        if await !isModelInstalled(localeIdentifier) { throw TranscriptionError.modelNotInstalled }
    }

    func transcribe(fileURL: URL, localeIdentifier: String,
                    onProgress: @escaping @Sendable (Double) -> Void) async throws -> Transcript {
        guard await Self.requestAuthorization() == .authorized else {
            throw TranscriptionError.notAuthorized
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)),
              recognizer.supportsOnDeviceRecognition else {
            throw TranscriptionError.modelNotInstalled
        }

        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.requiresOnDeviceRecognition = true      // offline only
        request.shouldReportPartialResults = false      // final result carries the timings

        return try await withCheckedThrowingContinuation { continuation in
            var didResume = false
            let finish: (Result<Transcript, Error>) -> Void = { result in
                guard !didResume else { return }
                didResume = true
                continuation.resume(with: result)
            }
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    finish(.failure(error))
                    return
                }
                guard let result, result.isFinal else { return }
                let transcription = result.bestTranscription
                let text = transcription.formattedString
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    finish(.failure(TranscriptionError.noSpeechFound))
                    return
                }
                let segments = transcription.segments.map {
                    TranscriptSegment(text: $0.substring, start: $0.timestamp, duration: $0.duration)
                }
                finish(.success(Transcript(text: text, segments: segments, detectedLocale: localeIdentifier)))
            }
        }
    }

    private static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }
}
