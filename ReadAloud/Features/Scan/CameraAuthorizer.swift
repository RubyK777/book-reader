import AVFoundation

/// Thin wrapper over `AVCaptureDevice` camera authorization so the scan
/// flow can prime/gate the document camera without touching AVFoundation.
enum CameraAuthorizer {
  static func status() -> AVAuthorizationStatus {
    AVCaptureDevice.authorizationStatus(for: .video)
  }

  static func request() async -> Bool {
    await AVCaptureDevice.requestAccess(for: .video)
  }
}
