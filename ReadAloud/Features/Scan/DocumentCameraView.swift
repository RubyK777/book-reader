import SwiftUI
import VisionKit

/// VisionKit document camera — deskewed, flattened page capture.
/// Replaces the old `CameraPicker`. Single-page this milestone:
/// `onScan` gets the FIRST captured page; multi-page batch is deferred.
struct DocumentCameraView: UIViewControllerRepresentable {
  let onScan: (UIImage) -> Void
  @Environment(\.dismiss) private var dismiss

  func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
    let controller = VNDocumentCameraViewController()
    controller.delegate = context.coordinator
    return controller
  }

  func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
    let parent: DocumentCameraView
    init(_ parent: DocumentCameraView) { self.parent = parent }

    func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                      didFinishWith scan: VNDocumentCameraScan) {
      if scan.pageCount > 0 {
        parent.onScan(scan.imageOfPage(at: 0))   // multi-page deferred
      }
      parent.dismiss()
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
      parent.dismiss()
    }

    func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                      didFailWithError error: Error) {
      parent.dismiss()
    }
  }
}
