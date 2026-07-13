import AVFoundation
import Observation

/// Record-and-compare for shadowing practice (product design Phase 3). Keeps only
/// the last take (a single temp file, D: no retention UI in v1). UI-free and
/// injectable; views observe `state` / `hasTake`.
///
/// Audio session: recording needs `.playAndRecord`; on stop we return to
/// `.playback` so SpeechPlayer's lock-screen/silent-switch behavior
/// (AUDIO_DESIGN) is untouched outside the recording moment.
@Observable
final class VoiceRecorder: NSObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    enum State { case idle, recording, playing }

    private(set) var state: State = .idle
    private(set) var hasTake = false
    /// True once the user has denied mic access — views hide the feature.
    private(set) var permissionDenied = false

    private var recorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?

    private let takeURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("shadowing-take.m4a")

    /// The last take's file, for transcribing (pronunciation check). Nil until recorded.
    var takeFileURL: URL? { hasTake ? takeURL : nil }

    /// Ask for mic access (primes the system prompt on first use).
    func requestPermission() async -> Bool {
        let granted = await AVAudioApplication.requestRecordPermission()
        permissionDenied = !granted
        return granted
    }

    func startRecording() {
        stopPlayback()
        guard AVAudioApplication.shared.recordPermission == .granted else { return }

        try? AVAudioSession.sharedInstance().setCategory(
            .playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
        try? AVAudioSession.sharedInstance().setActive(true)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        // Last take only: recording over the same URL replaces it.
        recorder = try? AVAudioRecorder(url: takeURL, settings: settings)
        recorder?.delegate = self
        if recorder?.record() == true {
            state = .recording
        }
    }

    func stopRecording() {
        recorder?.stop()
        recorder = nil
        restorePlaybackCategory()
        hasTake = FileManager.default.fileExists(atPath: takeURL.path)
        state = .idle
    }

    func playTake() {
        guard hasTake else { return }
        stopRecording()
        audioPlayer = try? AVAudioPlayer(contentsOf: takeURL)
        audioPlayer?.delegate = self
        if audioPlayer?.play() == true {
            state = .playing
        }
    }

    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        if state == .playing { state = .idle }
    }

    /// Remove the take (leaving a practice screen).
    func reset() {
        stopRecording()
        stopPlayback()
        try? FileManager.default.removeItem(at: takeURL)
        hasTake = false
        state = .idle
    }

    private func restorePlaybackCategory() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
    }

    // MARK: Delegates

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        hasTake = flag
        if state == .recording { state = .idle }
        restorePlaybackCategory()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if state == .playing { state = .idle }
    }
}
