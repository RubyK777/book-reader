import AVFoundation
import Observation

/// TTS engine + word-highlight source of truth (product design §5.4).
/// Owns the sentence queue; views observe currentSentenceIndex / highlightRange.
///
/// The Reader's player sets `managesNowPlaying` so it drives the lock-screen
/// Now Playing info and remote (play/pause/next/prev) commands; the short
/// replay players in Saved/Review do not, so they never fight over the
/// lock screen (AUDIO_DESIGN §7).
@Observable
final class SpeechPlayer: NSObject, AVSpeechSynthesizerDelegate, SentencePlaying {
    private let synthesizer = AVSpeechSynthesizer()

    private(set) var sentences: [String] = []
    private var languageCode = "en-US"
    private var nowPlayingTitle = "ReadAloud"

    private(set) var currentSentenceIndex: Int?
    private(set) var highlightRange: NSRange?
    private(set) var isSpeaking = false

    /// Displayed multiplier 0.5×–2.0×; applied on the next utterance.
    var speedMultiplier: Float = 1.0
    var repeatMode = false

    /// Set while we stop speech for a programmatic jump, so the resulting
    /// didFinish/didCancel doesn't also trigger auto-advance.
    private var isJumping = false

    /// Drives the lock-screen card + remote transport + interruption/route
    /// handling when this player owns them (the Reader's player); nil for the
    /// short throwaway replay players in Saved/Review (AUDIO_DESIGN §7).
    private var coordinator: AudioSessionCoordinator?

    init(managesNowPlaying: Bool = false) {
        super.init()
        synthesizer.delegate = self
        // .playback so audio plays even with the silent switch on, and keeps
        // playing when the screen locks (with the `audio` background mode).
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        if managesNowPlaying { coordinator = AudioSessionCoordinator(player: self) }
    }

    /// After returning from the background/lock screen, reconcile a stale
    /// `isSpeaking` if the OS suspended the synthesizer while we were away.
    func reconcile() {
        if isSpeaking && !synthesizer.isSpeaking && !synthesizer.isPaused {
            isSpeaking = false
            pushNowPlaying()
        }
    }

    /// Hand the current state to the lock-screen coordinator (no-op when this
    /// player doesn't own the lock screen).
    private func pushNowPlaying() {
        guard let coordinator else { return }
        if let index = currentSentenceIndex, sentences.indices.contains(index) {
            coordinator.update(.init(albumTitle: nowPlayingTitle, title: sentences[index],
                                     queueIndex: index, queueCount: sentences.count,
                                     rate: isSpeaking ? 1.0 : 0.0))
        } else {
            coordinator.update(.init(albumTitle: nowPlayingTitle, title: nowPlayingTitle,
                                     queueIndex: nil, queueCount: nil,
                                     rate: isSpeaking ? 1.0 : 0.0))
        }
    }

    func load(sentences: [String], languageCode: String, title: String? = nil) {
        stop()
        self.sentences = sentences
        self.languageCode = languageCode
        self.nowPlayingTitle = title ?? "ReadAloud"
    }

    /// Speak a single line as a one-item queue: normal (karaoke) playback, or the
    /// slow one-shot when `slow` is true. Collapses the load+play / load+speakOnce
    /// two-liner that was copied across the review, practice, and saved screens.
    func speakLine(_ text: String, languageCode: String, slow: Bool = false) {
        load(sentences: [text], languageCode: languageCode)
        if slow {
            speakOnce(text, slow: true)
        } else {
            play(at: 0)
        }
    }

    func play(at index: Int) {
        guard sentences.indices.contains(index) else { return }
        isJumping = synthesizer.isSpeaking
        synthesizer.stopSpeaking(at: .immediate)

        currentSentenceIndex = index
        highlightRange = nil

        let utterance = AVSpeechUtterance(string: sentences[index])
        utterance.voice = VoiceStore.resolvedVoice(for: languageCode)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * speedMultiplier
        try? AVAudioSession.sharedInstance().setActive(true)
        synthesizer.speak(utterance)
        isSpeaking = true
        pushNowPlaying()
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
        pushNowPlaying()
    }

    func next() {
        guard let index = currentSentenceIndex, index + 1 < sentences.count else { return }
        play(at: index + 1)
    }

    func previous() {
        guard let index = currentSentenceIndex, index > 0 else { return }
        play(at: index - 1)
    }

    /// The in-flight one-off utterance (speakOnce) and its completion, so the
    /// delegate can tell it apart from queue utterances.
    private var onceUtterance: AVSpeechUtterance?
    private var onceCompletion: (() -> Void)?

    /// One-off playback of a word/phrase/chunk (Learn view tap-to-hear) without
    /// touching the sentence queue. Interrupting a queued utterance goes
    /// through `isJumping` so didFinish/didCancel doesn't auto-advance
    /// (AUDIO_DESIGN state machine — preserve this). `completion` fires when
    /// the utterance finishes or is cancelled (e.g. by the next tap).
    func speakOnce(_ text: String, slow: Bool = false, completion: (() -> Void)? = nil) {
        isJumping = synthesizer.isSpeaking
        synthesizer.stopSpeaking(at: .immediate)   // may fire the old completion via didCancel

        // Abandon the queue position so didFinish can't auto-advance into the
        // queue after the one-off utterance ends.
        currentSentenceIndex = nil
        highlightRange = nil

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = VoiceStore.resolvedVoice(for: languageCode)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * (slow ? 0.5 : speedMultiplier)
        onceUtterance = utterance
        onceCompletion = completion
        try? AVAudioSession.sharedInstance().setActive(true)
        synthesizer.speak(utterance)
    }

    /// Fire-and-clear the once completion when its utterance ends either way.
    private func finishOnce(_ utterance: AVSpeechUtterance) {
        guard utterance === onceUtterance else { return }
        onceUtterance = nil
        let completion = onceCompletion
        onceCompletion = nil
        completion?()
    }

    func stop() {
        isJumping = true
        synthesizer.stopSpeaking(at: .immediate)
        currentSentenceIndex = nil
        highlightRange = nil
        isSpeaking = false
        coordinator?.clear()
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           willSpeakRangeOfSpeechString characterRange: NSRange,
                           utterance: AVSpeechUtterance) {
        highlightRange = characterRange
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        finishOnce(utterance)
        guard !isJumping else { isJumping = false; return }
        highlightRange = nil

        if repeatMode, let index = currentSentenceIndex {
            play(at: index)
        } else if let index = currentSentenceIndex, index + 1 < sentences.count {
            play(at: index + 1)
        } else {
            isSpeaking = false
            pushNowPlaying()   // reached the end of the page — reflect paused state
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didCancel utterance: AVSpeechUtterance) {
        finishOnce(utterance)
        isJumping = false
    }
}
