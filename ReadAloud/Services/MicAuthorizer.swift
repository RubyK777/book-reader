import AVFoundation

/// Thin wrapper over `AVAudioApplication` record permission so audio capture can
/// prime/gate the mic without touching AVFoundation directly (mirrors
/// `CameraAuthorizer`). Mic usage is already declared (for shadowing).
enum MicAuthorizer {
    static func status() -> AVAudioApplication.recordPermission {
        AVAudioApplication.shared.recordPermission
    }

    static func request() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }
}
