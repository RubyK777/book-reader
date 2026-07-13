import AVFoundation
import MediaPlayer
import Observation

/// Real-audio sentence playback for conversation sources (AUDIO_LEARNING_DESIGN
/// §5.2): plays the original recording, seeking to each sentence's `[start, end]`
/// and stepping to the next when the boundary passes (timer-gated, mirroring
/// `SpeechPlayer`'s sentence stepping). Sentence-level karaoke — no word ranges
/// yet, so `highlightRange` stays nil and the Reader highlights the whole active
/// sentence. Conforms to `SentencePlaying` so the Reader is engine-agnostic.
@Observable
final class RecordingPlayer: NSObject, SentencePlaying {
    private(set) var currentSentenceIndex: Int?
    private(set) var highlightRange: NSRange?    // word-level karaoke, driven by playback time
    private(set) var isSpeaking = false

    var speedMultiplier: Float = 1.0 {
        didSet { player?.rate = speedMultiplier }
    }
    var repeatMode = false

    private var player: AVAudioPlayer?
    private var sentenceCount: Int
    private let ranges: [(start: Double, end: Double)]
    private let wordTimings: [[WordTiming]]
    private var boundaryTimer: Timer?
    private var tempURL: URL?

    /// The Reader's player sets `managesNowPlaying` so it drives the lock-screen
    /// Now Playing card + remote commands (mirrors `SpeechPlayer`). Sentence
    /// texts/title are kept only for that display; playback itself uses `ranges`.
    private let managesNowPlaying: Bool
    private var sentences: [String] = []
    private var title = "ReadAloud"
    private var interruptedIndex: Int?

    private var nowPlayingTitle: String { title }

    /// `ranges[i]` is sentence `i`'s time window; `wordTimings[i]` its per-word
    /// karaoke timings (empty ⇒ sentence-level highlight only).
    init(audioData: Data,
         ranges: [(start: Double, end: Double)],
         wordTimings: [[WordTiming]] = [],
         managesNowPlaying: Bool = false) {
        self.ranges = ranges
        self.wordTimings = wordTimings
        self.sentenceCount = ranges.count
        self.managesNowPlaying = managesNowPlaying
        super.init()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        if let url = AudioFileStore.materialize(audioData, id: UUID()) {
            tempURL = url
            player = try? AVAudioPlayer(contentsOf: url)
            player?.enableRate = true
            player?.prepareToPlay()
        }
        if managesNowPlaying {
            configureRemoteCommands()
            observeAudioSession()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if managesNowPlaying {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
    }

    func load(sentences: [String], languageCode: String, title: String?) {
        // Real-audio playback uses `ranges`; keep the strings/title only to label
        // the lock-screen Now Playing card. Sync the count defensively.
        self.sentences = sentences
        self.title = title.nonBlank ?? "ReadAloud"
        sentenceCount = min(sentences.count, ranges.count)
    }

    func play(at index: Int) {
        guard ranges.indices.contains(index), let player else { return }
        stopTimer()
        currentSentenceIndex = index
        highlightRange = nil
        player.rate = speedMultiplier
        player.currentTime = ranges[index].start
        player.play()
        isSpeaking = true
        startBoundaryTimer(for: index)
        updateNowPlaying()
    }

    func togglePlayPause() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            stopTimer()
            isSpeaking = false
            updateNowPlaying()
        } else {
            play(at: currentSentenceIndex ?? 0)
        }
    }

    func next() {
        guard let index = currentSentenceIndex, index + 1 < ranges.count else { return }
        play(at: index + 1)
    }

    func previous() {
        guard let index = currentSentenceIndex, index > 0 else { return }
        play(at: index - 1)
    }

    func stop() {
        stopTimer()
        player?.pause()
        player?.currentTime = 0
        currentSentenceIndex = nil
        highlightRange = nil
        isSpeaking = false
        if managesNowPlaying {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
    }

    func reconcile() {
        if isSpeaking && player?.isPlaying == false {
            isSpeaking = false
            updateNowPlaying()
        }
    }

    // MARK: - Boundary stepping

    private func startBoundaryTimer(for index: Int) {
        let end = ranges[index].end
        let words = index < wordTimings.count ? wordTimings[index] : []
        boundaryTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            guard let self, let player = self.player else { return }
            let time = player.currentTime
            // Word-level karaoke: light up the most recent word that has started.
            if let word = words.last(where: { $0.start <= time }) {
                self.highlightRange = NSRange(location: word.location, length: word.length)
            } else {
                self.highlightRange = nil
            }
            if time >= end || !player.isPlaying {
                self.sentenceBoundaryReached(index)
            }
        }
    }

    private func sentenceBoundaryReached(_ index: Int) {
        stopTimer()
        if repeatMode {
            play(at: index)   // replay this sentence (real seek)
        } else if index + 1 < ranges.count {
            // Natural advance: the audio is already flowing into the next
            // sentence, so DON'T re-seek (that stutters) — just move the
            // highlight/boundary. play(at:) re-seeks only for manual jumps.
            currentSentenceIndex = index + 1
            highlightRange = nil
            startBoundaryTimer(for: index + 1)
            updateNowPlaying()   // advance the lock-screen card with the audio
        } else {
            player?.pause()
            isSpeaking = false
            updateNowPlaying()   // reached the end — reflect paused state
        }
    }

    private func stopTimer() {
        boundaryTimer?.invalidate()
        boundaryTimer = nil
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
            MPNowPlayingInfoPropertyPlaybackRate: isSpeaking ? Double(speedMultiplier) : 0.0,
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
    /// `.ended` resume the interrupted sentence only if the system permits.
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
                play(at: index)
            }
        @unknown default:
            break
        }
    }

    /// Headphones unplugged (`.oldDeviceUnavailable`): pause, matching the system
    /// convention so audio doesn't suddenly blast from the speaker.
    @objc private func handleRouteChange(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw),
              reason == .oldDeviceUnavailable else { return }
        if isSpeaking { togglePlayPause() }
    }
}
