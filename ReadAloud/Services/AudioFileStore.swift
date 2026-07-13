import Foundation
import AVFoundation

/// Manages captured/imported audio on disk (AUDIO_LEARNING_DESIGN §5.3): a
/// recording target, extracting a video's audio track locally, importing an
/// audio file, and materializing a persisted SwiftData blob to a temp file for
/// playback. UI-free (CLAUDE.md library rule); fully offline.
enum AudioFileStore {
    /// Directory for in-progress captures (kept out of the SwiftData store).
    static var captureDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("AudioCaptures", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A fresh `.m4a` URL to record into.
    static func newRecordingURL(id: UUID) -> URL {
        captureDir.appendingPathComponent("capture-\(id.uuidString).m4a")
    }

    /// Own an imported file: extract a movie's audio track to `.m4a`, or copy an
    /// audio file into our capture dir. Returns nil on failure. Offline.
    static func importMedia(from url: URL, id: UUID) async -> URL? {
        // Security-scoped access for files picked outside the sandbox.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let asset = AVURLAsset(url: url)
        let hasVideo = (try? await asset.loadTracks(withMediaType: .video))?.isEmpty == false
        if hasVideo {
            return await extractAudio(from: asset, id: id)
        }
        // Plain audio — copy it in, preserving extension.
        let dest = captureDir.appendingPathComponent("import-\(id.uuidString).\(url.pathExtension.isEmpty ? "m4a" : url.pathExtension)")
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: url, to: dest)
            return dest
        } catch {
            return nil
        }
    }

    private static func extractAudio(from asset: AVURLAsset, id: UUID) async -> URL? {
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { return nil }
        let out = captureDir.appendingPathComponent("import-\(id.uuidString).m4a")
        try? FileManager.default.removeItem(at: out)
        do {
            try await export.export(to: out, as: .m4a)
            return out
        } catch {
            return nil
        }
    }

    /// Read a captured file's bytes for persistence.
    static func data(at url: URL) -> Data? {
        try? Data(contentsOf: url)
    }

    /// The clip's duration in seconds.
    static func duration(of url: URL) async -> Double {
        let seconds = try? await AVURLAsset(url: url).load(.duration).seconds
        return (seconds?.isFinite == true) ? (seconds ?? 0) : 0
    }

    /// Write a persisted audio blob to a temp file so `AVAudioPlayer` can open it.
    static func materialize(_ data: Data, id: UUID) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("play-\(id.uuidString).m4a")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    /// Best-effort cleanup of a temporary capture file.
    static func discard(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
