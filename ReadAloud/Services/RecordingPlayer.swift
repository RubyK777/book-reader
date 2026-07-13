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
    let highlightRange: NSRange? = nil          // sentence-level only for now
    private(set) var isSpeaking = false

    var speedMultiplier: Float = 1.0 {
        didSet { player?.rate = speedMultiplier }
    }
    var repeatMode = false

    private var player: AVAudioPlayer?
    private var sentenceCount: Int
    private let ranges: [(start: Double, end: Double)]
    private var boundaryTimer: Timer?
    private var tempURL: URL?

    /// `ranges[i]` is sentence `i`'s time window into the clip, in play order.
    init(audioData: Data, ranges: [(start: Double, end: Double)]) {
        self.ranges = ranges
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
        boundaryTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            guard let self, let player = self.player else { return }
            if player.currentTime >= end || !player.isPlaying {
                self.sentenceBoundaryReached(index)
            }
        }
    }

    private func sentenceBoundaryReached(_ index: Int) {
        stopTimer()
        if repeatMode {
            play(at: index)
        } else if index + 1 < ranges.count {
            play(at: index + 1)
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
