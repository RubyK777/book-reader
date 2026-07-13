import Foundation
import AVFoundation
import MediaPlayer

/// Lock-screen Now Playing card + remote transport + audio-session robustness,
/// shared by `SpeechPlayer` (TTS) and `RecordingPlayer` (real audio) so the two
/// engines don't each re-implement `MPNowPlayingInfoCenter` /
/// `MPRemoteCommandCenter` / interruption + route handling (DECISIONS #65).
///
/// The owning player creates one when it drives the lock screen (`managesNowPlaying`),
/// holds it strongly, and pushes a `NowPlaying` snapshot on every state change.
/// The coordinator drives the player back through the `SentencePlaying` transport
/// (a weak reference, so there's no retain cycle) and owns the interrupted-sentence
/// bookkeeping. It also removes its remote-command targets + observers on deinit —
/// which the hand-rolled per-player versions never did.
final class AudioSessionCoordinator: NSObject {

    /// What the player wants shown on the lock-screen card right now.
    struct NowPlaying {
        var albumTitle: String
        var title: String
        var queueIndex: Int?
        var queueCount: Int?
        var rate: Double        // 0 while paused
    }

    private weak var player: (any SentencePlaying)?
    private var interruptedIndex: Int?
    private var commandTargets: [(MPRemoteCommand, Any)] = []

    init(player: any SentencePlaying) {
        self.player = player
        super.init()
        configureRemoteCommands()
        observeAudioSession()
    }

    deinit {
        for (command, target) in commandTargets { command.removeTarget(target) }
        NotificationCenter.default.removeObserver(self)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Now Playing

    func update(_ info: NowPlaying) {
        var dict: [String: Any] = [
            MPMediaItemPropertyAlbumTitle: info.albumTitle,
            MPMediaItemPropertyTitle: info.title,
            MPNowPlayingInfoPropertyPlaybackRate: info.rate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
        ]
        if let index = info.queueIndex { dict[MPNowPlayingInfoPropertyPlaybackQueueIndex] = index }
        if let count = info.queueCount { dict[MPNowPlayingInfoPropertyPlaybackQueueCount] = count }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = dict
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Remote commands

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        register(center.playCommand) { [weak self] _ in
            guard let player = self?.player else { return .commandFailed }
            if !player.isSpeaking { player.togglePlayPause() }
            return .success
        }
        register(center.pauseCommand) { [weak self] _ in
            guard let player = self?.player else { return .commandFailed }
            if player.isSpeaking { player.togglePlayPause() }
            return .success
        }
        register(center.togglePlayPauseCommand) { [weak self] _ in
            self?.player?.togglePlayPause(); return .success
        }
        register(center.nextTrackCommand) { [weak self] _ in self?.player?.next(); return .success }
        register(center.previousTrackCommand) { [weak self] _ in self?.player?.previous(); return .success }
        // Sentences, not time, are the unit — skip/scrub commands don't apply.
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
        center.changePlaybackPositionCommand.isEnabled = false
    }

    private func register(_ command: MPRemoteCommand,
                          _ handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus) {
        commandTargets.append((command, command.addTarget(handler: handler)))
    }

    // MARK: - Audio-session robustness

    private func observeAudioSession() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(handleInterruption(_:)),
                       name: AVAudioSession.interruptionNotification,
                       object: AVAudioSession.sharedInstance())
        nc.addObserver(self, selector: #selector(handleRouteChange(_:)),
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
            if let player, player.isSpeaking {
                interruptedIndex = player.currentSentenceIndex
                player.stop()
            }
        case .ended:
            guard let index = interruptedIndex else { return }
            interruptedIndex = nil
            let options = (info[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map(AVAudioSession.InterruptionOptions.init)
            if options?.contains(.shouldResume) == true { player?.play(at: index) }
        @unknown default:
            break
        }
    }

    /// Headphones unplugged (`.oldDeviceUnavailable`): stop, matching the system
    /// convention so audio doesn't suddenly blast from the speaker.
    @objc private func handleRouteChange(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw),
              reason == .oldDeviceUnavailable else { return }
        if let player, player.isSpeaking { player.stop() }
    }
}
