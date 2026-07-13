import AVFoundation
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

    /// `ranges[i]` is sentence `i`'s time window; `wordTimings[i]` its per-word
    /// karaoke timings (empty ⇒ sentence-level highlight only).
    init(audioData: Data,
         ranges: [(start: Double, end: Double)],
         wordTimings: [[WordTiming]] = []) {
        self.ranges = ranges
        self.wordTimings = wordTimings
        self.sentenceCount = ranges.count
        super.init()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        if let url = AudioFileStore.materialize(audioData, id: UUID()) {
            tempURL = url
            player = try? AVAudioPlayer(contentsOf: url)
            player?.enableRate = true
            player?.prepareToPlay()
        }
    }

    func load(sentences: [String], languageCode: String, title: String?) {
        // Sentence strings/title aren't needed for real-audio playback (the
        // Reader owns the text); keep the count in sync defensively.
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
    }

    func togglePlayPause() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            stopTimer()
            isSpeaking = false
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
    }

    func reconcile() {
        if isSpeaking && player?.isPlaying == false {
            isSpeaking = false
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
        } else {
            player?.pause()
            isSpeaking = false
        }
    }

    private func stopTimer() {
        boundaryTimer?.invalidate()
        boundaryTimer = nil
    }
}
