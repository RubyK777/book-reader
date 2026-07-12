import SwiftUI
import VisionKit

/// VisionKit document camera — deskewed, flattened page capture. Returns every
/// page captured in the session (VisionKit lets you shoot several before Save),
/// so a single shot yields one image and a chapter yields many.
struct DocumentCameraView: UIViewControllerRepresentable {
  let onScan: ([UIImage]) -> Void
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
      let pages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
      if !pages.isEmpty { parent.onScan(pages) }
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
