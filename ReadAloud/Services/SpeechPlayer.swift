import AVFoundation
import Observation

/// TTS engine + word-highlight source of truth (PROJECT_PLAN.md §5.4).
/// Owns the sentence queue; views observe currentSentenceIndex / highlightRange.
@Observable
final class SpeechPlayer: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()

    private(set) var sentences: [String] = []
    private var languageCode = "en-US"

    private(set) var currentSentenceIndex: Int?
    private(set) var highlightRange: NSRange?
    private(set) var isSpeaking = false

    /// Displayed multiplier 0.5×–1.0×; applied on the next utterance.
    var speedMultiplier: Float = 1.0
    var repeatMode = false

    /// Set while we stop speech for a programmatic jump, so the resulting
    /// didFinish/didCancel doesn't also trigger auto-advance.
    private var isJumping = false

    override init() {
        super.init()
        synthesizer.delegate = self
        // .playback so audio plays even with the silent switch on.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
    }

    func load(sentences: [String], languageCode: String) {
        stop()
        self.sentences = sentences
        self.languageCode = languageCode
    }

    func play(at index: Int) {
        guard sentences.indices.contains(index) else { return }
        isJumping = synthesizer.isSpeaking
        synthesizer.stopSpeaking(at: .immediate)

        currentSentenceIndex = index
        highlightRange = nil

        let utterance = AVSpeechUtterance(string: sentences[index])
        utterance.voice = AVSpeechSynthesisVoice(language: languageCode)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * speedMultiplier
        try? AVAudioSession.sharedInstance().setActive(true)
        synthesizer.speak(utterance)
        isSpeaking = true
    }

    func togglePlayPause() {
        if synthesizer.isSpeaking && !synthesizer.isPaused {
            synthesizer.pauseSpeaking(at: .word)
            isSpeaking = false
        } else if synthesizer.isPaused {
            synthesizer.continueSpeaking()
            isSpeaking = true
        } else {
            play(at: currentSentenceIndex ?? 0)
        }
    }

    func next() {
        guard let index = currentSentenceIndex, index + 1 < sentences.count else { return }
        play(at: index + 1)
    }

    func previous() {
        guard let index = currentSentenceIndex, index > 0 else { return }
        play(at: index - 1)
    }

    func stop() {
        isJumping = true
        synthesizer.stopSpeaking(at: .immediate)
        currentSentenceIndex = nil
        highlightRange = nil
        isSpeaking = false
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           willSpeakRangeOfSpeechString characterRange: NSRange,
                           utterance: AVSpeechUtterance) {
        highlightRange = characterRange
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        guard !isJumping else { isJumping = false; return }
        highlightRange = nil

        if repeatMode, let index = currentSentenceIndex {
            play(at: index)
        } else if let index = currentSentenceIndex, index + 1 < sentences.count {
            play(at: index + 1)
        } else {
            isSpeaking = false
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didCancel utterance: AVSpeechUtterance) {
        isJumping = false
    }
}
