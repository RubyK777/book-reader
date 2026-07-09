import SwiftUI
import UIKit

/// Presents the system share sheet for a file URL (e.g. the JSON export).
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Identifiable URL wrapper so an export file can drive `.sheet(item:)`.
struct ShareableFile: Identifiable {
    let url: URL
    var id: String { url.path }
}
