import AVFoundation
import Observation

/// Live microphone capture to `.m4a` with a normalized level for the meter and
/// an elapsed clock. Focused on capture only (playback/transcription live
/// elsewhere). Mirrors `VoiceRecorder`'s AVAudioRecorder setup.
@Observable
final class AudioCaptureRecorder: NSObject, AVAudioRecorderDelegate {
    enum State { case idle, recording, stopped }

    private(set) var state: State = .idle
    private(set) var level: Float = 0          // 0…1 for the meter
    private(set) var elapsed: TimeInterval = 0
    private(set) var fileURL: URL?

    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private let id = UUID()

    func start() {
        let url = AudioFileStore.newRecordingURL(id: id)
        try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try? AVAudioSession.sharedInstance().setActive(true)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        guard let recorder = try? AVAudioRecorder(url: url, settings: settings) else { return }
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        recorder.record()
        self.recorder = recorder
        fileURL = url
        state = .recording
        startMeter()
    }

    func stop() {
        recorder?.stop()
        stopMeter()
        state = .stopped
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func cancel() {
        recorder?.stop()
        stopMeter()
        AudioFileStore.discard(fileURL)
        fileURL = nil
        elapsed = 0
        state = .idle
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startMeter() {
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.recorder else { return }
            recorder.updateMeters()
            self.level = Self.normalized(recorder.averagePower(forChannel: 0))
            self.elapsed = recorder.currentTime
        }
    }

    private func stopMeter() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    /// dB power (−160…0) → 0…1, floored at a usable noise gate.
    private static func normalized(_ db: Float) -> Float {
        let floorDb: Float = -50
        guard db > floorDb else { return 0 }
        return (db - floorDb) / -floorDb
    }
}
