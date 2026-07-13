import AVFoundation
import MediaPlayer
import Observation

/// TTS engine + word-highlight source of truth (PROJECT_PLAN.md §5.4).
/// Owns the sentence queue; views observe currentSentenceIndex / highlightRange.
///
/// The Reader's player sets `managesNowPlaying` so it drives the lock-screen
/// Now Playing info and remote (play/pause/next/prev) commands; the short
/// replay players in Saved/Review do not, so they never fight over the
/// lock screen (AUDIO_DESIGN §7).
@Observable
final class SpeechPlayer: NSObject, AVSpeechSynthesizerDelegate {
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

    /// The sentence to resume after an interruption (phone call, Siri) that
    /// paused us; nil when we weren't interrupted mid-speech.
    private var interruptedIndex: Int?

    /// Whether this player owns the lock-screen Now Playing info + remote commands.
    private let managesNowPlaying: Bool

    init(managesNowPlaying: Bool = false) {
        self.managesNowPlaying = managesNowPlaying
        super.init()
        synthesizer.delegate = self
        // .playback so audio plays even with the silent switch on, and keeps
        // playing when the screen locks (with the `audio` background mode).
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        observeAudioSession()
        if managesNowPlaying { configureRemoteCommands() }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if managesNowPlaying {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
    }

    /// After returning from the background/lock screen, reconcile a stale
    /// `isSpeaking` if the OS suspended the synthesizer while we were away.
    func reconcile() {
        if isSpeaking && !synthesizer.isSpeaking && !synthesizer.isPaused {
            isSpeaking = false
            updateNowPlaying()
        }
    }

    // MARK: - Lock-screen: Now Playing + remote commands

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if !self.isSpeaking { self.togglePlayPause() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if self.isSpeaking { self.togglePlayPause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause(); return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in self?.next(); return .success }
        center.previousTrackCommand.addTarget { [weak self] _ in self?.previous(); return .success }
        // Sentences, not time, are the unit — skip/scrub commands don't apply.
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
        center.changePlaybackPositionCommand.isEnabled = false
    }

    private func updateNowPlaying() {
        guard managesNowPlaying else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyAlbumTitle: nowPlayingTitle,
            MPNowPlayingInfoPropertyPlaybackRate: isSpeaking ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
        ]
        if let index = currentSentenceIndex, sentences.indices.contains(index) {
            info[MPMediaItemPropertyTitle] = sentences[index]
            info[MPNowPlayingInfoPropertyPlaybackQueueCount] = sentences.count
            info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = index
        } else {
            info[MPMediaItemPropertyTitle] = nowPlayingTitle
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Audio session robustness

    private func observeAudioSession() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(handleInterruption(_:)),
                           name: AVAudioSession.interruptionNotification,
                           object: AVAudioSession.sharedInstance())
        center.addObserver(self, selector: #selector(handleRouteChange(_:)),
                           name: AVAudioSession.routeChangeNotification,
                           object: AVAudioSession.sharedInstance())
    }

    /// Phone call / Siri / another app grabs audio: pause on `.began`, and on
    /// `.ended` resume from the current sentence only if the system says we may.
    @objc private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }

        switch type {
        case .began:
            if isSpeaking {
                interruptedIndex = currentSentenceIndex
                stop()
            }
        case .ended:
            guard let index = interruptedIndex else { return }
            interruptedIndex = nil
            let options = (info[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init)
            if options?.contains(.shouldResume) == true {
                play(at: index)   // reactivates the session and replays the sentence
            }
        @unknown default:
            break
        }
    }

    /// Headphones unplugged (`.oldDeviceUnavailable`): pause, matching the
    /// system convention so audio doesn't suddenly blast from the speaker.
    @objc private func handleRouteChange(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw),
              reason == .oldDeviceUnavailable else { return }
        if isSpeaking { stop() }
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
        updateNowPlaying()
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
        updateNowPlaying()
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
        if managesNowPlaying {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
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
            updateNowPlaying()   // reached the end of the page — reflect paused state
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didCancel utterance: AVSpeechUtterance) {
        finishOnce(utterance)
        isJumping = false
    }
}
