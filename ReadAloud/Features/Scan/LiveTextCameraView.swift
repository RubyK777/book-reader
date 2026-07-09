import SwiftUI
import VisionKit

/// Live Text camera: the viewfinder highlights recognized text in real time
/// (so you can see the page is readable) and a manual shutter captures a still
/// for OCR — no auto-shutter to fight, unlike the document scanner.
struct LiveTextCameraView: View {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var proxy = ScannerProxy()
    @State private var isCapturing = false

    /// Requires a device with the Neural Engine + granted camera access.
    /// False on the Simulator, so the scan flow falls back to Import Photo.
    static var isSupported: Bool { DataScannerViewController.isSupported }

    var body: some View {
        ZStack {
            DataScannerRepresentable(proxy: proxy)
                .ignoresSafeArea()

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(DesignSystem.Spacing.md)
                            .background(.black.opacity(0.4), in: Circle())
                    }
                    Spacer()
                }
                .padding()

                Spacer()

                Text("Fill the frame with the page — text lights up when it's readable, then tap to capture.")
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    .background(.black.opacity(0.5), in: Capsule())
                    .padding(.horizontal, DesignSystem.Spacing.xl)

                shutterButton
                    .padding(.top, DesignSystem.Spacing.lg)
                    .padding(.bottom, DesignSystem.Spacing.xl)
            }
        }
        .background(.black)
    }

    private var shutterButton: some View {
        Button {
            capture()
        } label: {
            ZStack {
                Circle().strokeBorder(.white, lineWidth: 5).frame(width: 74, height: 74)
                Circle().fill(.white).frame(width: 60, height: 60)
                if isCapturing {
                    ProgressView().tint(.black)
                }
            }
        }
        .disabled(isCapturing)
        .accessibilityLabel("Capture page")
    }

    private func capture() {
        isCapturing = true
        Task {
            if let image = await proxy.capture() {
                onCapture(image)
                dismiss()
            } else {
                isCapturing = false
            }
        }
    }
}

/// Bridges the SwiftUI shutter button to the underlying scanner's async capture.
@Observable
final class ScannerProxy {
    fileprivate weak var scanner: DataScannerViewController?

    func capture() async -> UIImage? {
        guard let scanner else { return nil }
        return try? await scanner.capturePhoto()
    }
}

private struct DataScannerRepresentable: UIViewControllerRepresentable {
    let proxy: ScannerProxy

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: false,
            isHighlightingEnabled: true)   // the live "Live Text" highlight
        proxy.scanner = scanner
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        try? scanner.startScanning()
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: ()) {
        scanner.stopScanning()
    }
}
