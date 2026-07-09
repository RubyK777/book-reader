import SwiftUI
import PhotosUI
import VisionKit

/// Capture-first scan flow presented as a sheet.
/// `book == nil` → Library entry (book assigned in review);
/// `book != nil` → Book-detail "Add Page" (page ingested into that book).
/// Steps: capture (doc camera / import) → OCR → review → ingest → dismiss+push.
struct ScanFlowView: View {
  let book: Book?

  @Environment(\.dismiss) private var dismiss

  @State private var step: Step = .capture
  @State private var isReading = false
  @State private var errorMessage: String?
  @State private var pickerItem: PhotosPickerItem?
  @State private var showCamera = false
  @State private var showLiveText = false
  /// Optional pre-capture hint biasing Vision toward a language (Library path
  /// only; Add Page already knows the book's language). `nil` = auto-detect.
  @State private var languageHint: String?

  private enum Step {
    case capture
    case review(UIImage, OCRResult)
  }

  private var docScannerSupported: Bool { VNDocumentCameraViewController.isSupported }
  /// A camera exists if either the Live Text scanner or the document scanner does.
  private var anyCameraSupported: Bool { LiveTextCameraView.isSupported || docScannerSupported }

  var body: some View {
    NavigationStack {
      switch step {
      case .capture:
        captureView
      case let .review(image, result):
        OCRReviewView(image: image, result: result, book: book) {
          step = .capture
        }
      }
    }
  }

  // MARK: Capture step

  private var captureView: some View {
    VStack(spacing: DesignSystem.Spacing.lg) {
      if isReading {
        ProgressView("Reading page…")
      } else {
        Image(systemName: "doc.text.viewfinder")
          .font(.system(size: 56))
          .foregroundStyle(.secondary)
        Text(book == nil ? "Scan a book page" : "Add a page")
          .font(.headline)
        Text("Any supported language — detected automatically.")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)

        if book == nil {
          Picker("Page language", selection: $languageHint) {
            Text("Auto-detect").tag(String?.none)
            ForEach(LanguageCatalog.options, id: \.code) { lang in
              Text(lang.name).tag(String?.some(lang.code))
            }
          }
          .pickerStyle(.menu)
        }

        if let errorMessage {
          Text(errorMessage)
            .font(.callout)
            .foregroundStyle(.red)
            .multilineTextAlignment(.center)
        }

        VStack(spacing: DesignSystem.Spacing.sm) {
          if anyCameraSupported {
            Button { startCamera() } label: {
              Label("Scan Page", systemImage: "text.viewfinder")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
          }
          PhotosPicker(selection: $pickerItem, matching: .images) {
            Label("Import Photo", systemImage: "photo")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
        }
        .padding(.horizontal, DesignSystem.Spacing.xl)
      }
    }
    .padding()
    .navigationTitle("Scan")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") { dismiss() }
      }
    }
    .fullScreenCover(isPresented: $showLiveText) {
      LiveTextCameraView { image in handle(image) }
    }
    .fullScreenCover(isPresented: $showCamera) {
      DocumentCameraView { image in handle(image) }
        .ignoresSafeArea()
    }
    .onChange(of: pickerItem) { _, item in loadPicked(item) }
  }

  // MARK: Actions

  private func startCamera() {
    Task { @MainActor in
      let granted: Bool
      switch CameraAuthorizer.status() {
      case .authorized: granted = true
      case .notDetermined: granted = await CameraAuthorizer.request()
      default: granted = false
      }
      guard granted else {
        errorMessage = "Camera access is off — enable it in Settings, or import a photo."
        return
      }
      // Prefer the easy Live Text camera; fall back to the document scanner
      // on devices without live scanning.
      if LiveTextCameraView.isSupported {
        showLiveText = true
      } else {
        showCamera = true
      }
    }
  }

  private func loadPicked(_ item: PhotosPickerItem?) {
    guard let item else { return }
    Task { @MainActor in
      pickerItem = nil
      if let data = try? await item.loadTransferable(type: Data.self),
         let image = UIImage(data: data) {
        handle(image)
      } else {
        errorMessage = "Couldn't load that photo."
      }
    }
  }

  private func handle(_ image: UIImage) {
    errorMessage = nil
    isReading = true
    Task { @MainActor in
      do {
        let result = try await PageIngestor().recognize(image, languageHint: languageHint ?? book?.languageCode)
        isReading = false
        if result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          errorMessage = "No text found — try a flatter page with more light."
        } else {
          step = .review(image, result)
        }
      } catch {
        isReading = false
        errorMessage = "Couldn't read this page. Try again with more light."
      }
    }
  }
}
