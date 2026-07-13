import Foundation
import Observation

/// The playback surface the Reader depends on, so it can drive either engine
/// without branching on source kind (AUDIO_LEARNING_DESIGN §5.2): `SpeechPlayer`
/// (TTS) for text sources, `RecordingPlayer` (seek real audio) for conversation
/// sources. Both are `@Observable`; the Reader observes `currentSentenceIndex` /
/// `highlightRange` / `isSpeaking` and calls the transport methods.
protocol SentencePlaying: AnyObject, Observable {
    /// The sentence currently playing (drives the active-card highlight).
    var currentSentenceIndex: Int? { get }
    /// Word-level range within the active sentence (TTS only; nil ⇒ sentence-level).
    var highlightRange: NSRange? { get }
    var isSpeaking: Bool { get }
    var speedMultiplier: Float { get set }
    var repeatMode: Bool { get set }

    func load(sentences: [String], languageCode: String, title: String?)
    func play(at index: Int)
    func togglePlayPause()
    func next()
    func previous()
    func stop()
    /// Reconcile stale `isSpeaking` after returning from background/lock.
    func reconcile()
}
