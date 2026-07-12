import SwiftUI
import VisionKit

/// Live Text camera: the viewfinder highlights recognized text in real time
/// (so you can see the page is readable) and a manual shutter captures a still
/// for OCR — no auto-shutter or crop box to fight, unlike the document scanner.
/// In `allowsMultiple` mode the shutter keeps adding pages until you tap Done,
/// so a chapter is captured with the same tap-to-shoot feel as one page.
struct LiveTextCameraView: View {
    var allowsMultiple: Bool = false
    /// Every captured page, in order. One element in single-page mode.
    let onFinish: ([UIImage]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var proxy = ScannerProxy()
    @State private var isCapturing = false
    @State private var captured: [UIImage] = []

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
                    if allowsMultiple && !captured.isEmpty {
                        Button { finish() } label: {
                            Text("Done (\(captured.count))")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .padding(.horizontal, DesignSystem.Spacing.md)
                                .padding(.vertical, DesignSystem.Spacing.sm)
                                .background(Theme.accent, in: Capsule())
                        }
                        .accessibilityLabel("Done, \(captured.count) pages")
                    }
                }
                .padding()

                Spacer()

                Text(promptText)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    .background(.black.opacity(0.5), in: Capsule())
                    .padding(.horizontal, DesignSystem.Spacing.xl)

                if allowsMultiple && !captured.isEmpty {
                    thumbnailStrip
                        .padding(.top, DesignSystem.Spacing.sm)
                }

                shutterButton
                    .padding(.top, DesignSystem.Spacing.lg)
                    .padding(.bottom, DesignSystem.Spacing.xl)
            }
        }
        .background(.black)
    }

    private var promptText: String {
        allowsMultiple
            ? "Tap to capture each page. Add as many as you like, then tap Done."
            : "Fill the frame with the page — text lights up when it's readable, then tap to capture."
    }

    /// Running strip of captured pages so you can see what's been added; tap the
    /// last one to remove it if a shot came out wrong.
    private var thumbnailStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                ForEach(Array(captured.enumerated()), id: \.offset) { index, image in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
                        .overlay(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                            .stroke(.white.opacity(0.6), lineWidth: 1))
                        .overlay(alignment: .topTrailing) {
                            if index == captured.count - 1 {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.white, .black.opacity(0.5))
                                    .offset(x: 4, y: -4)
                            }
                        }
                        .onTapGesture {
                            if index == captured.count - 1 { captured.removeLast() }
                        }
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
        }
        .frame(height: 60)
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
                captured.append(image)
                isCapturing = false
                if allowsMultiple {
                    Haptics.select()   // per-page feedback; keep scanning
                } else {
                    finish()
                }
            } else {
                isCapturing = false
            }
        }
    }

    private func finish() {
        guard !captured.isEmpty else { dismiss(); return }
        onFinish(captured)
        dismiss()
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
