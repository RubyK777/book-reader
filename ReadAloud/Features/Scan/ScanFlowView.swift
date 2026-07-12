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
  @State private var showBatchCamera = false
  @State private var showLiveText = false
  @State private var showLiveTextBatch = false
  /// Optional pre-capture hint biasing Vision toward a language (Library path
  /// only; Add Page already knows the book's language). `nil` = auto-detect.
  @State private var languageHint: String?

  private enum Step {
    case capture
    case review(UIImage, OCRResult)
    case reviewBatch([BatchReviewView.Page], String)
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
      case let .reviewBatch(pages, language):
        BatchReviewView(pages: pages, languageCode: language, book: book) {
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
        Text(book == nil ? "Scan a page, sign, or menu" : "Add a page")
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
          if anyCameraSupported {
            Button { startBatchCamera() } label: {
              Label("Scan Multiple Pages", systemImage: "doc.on.doc")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
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
      LiveTextCameraView { images in handleScanned(images) }
    }
    .fullScreenCover(isPresented: $showLiveTextBatch) {
      LiveTextCameraView(allowsMultiple: true) { images in handleScanned(images) }
    }
    .fullScreenCover(isPresented: $showCamera) {
      DocumentCameraView { images in handleScanned(images) }
        .ignoresSafeArea()
    }
    .fullScreenCover(isPresented: $showBatchCamera) {
      DocumentCameraView { images in handleScanned(images) }
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

  /// Multi-page capture. Same Live Text tap-to-shoot camera (no crop box to
  /// adjust), collecting several pages before Done; the document scanner is a
  /// fallback only where Live Text isn't available.
  private func startBatchCamera() {
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
      if LiveTextCameraView.isSupported {
        showLiveTextBatch = true
      } else {
        showBatchCamera = true
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
          errorMessage = "No text found — flatten the page, add light, and retake."
        } else {
          step = .review(image, result)
        }
      } catch {
        isReading = false
        errorMessage = "Couldn't read this page — retake it with more light."
      }
    }
  }

  /// Route a camera result: one page uses the single-page review; several go to
  /// the batch review (OCR'd together, saved into one book).
  private func handleScanned(_ images: [UIImage]) {
    guard !images.isEmpty else { return }
    if images.count == 1 {
      handle(images[0])
    } else {
      Task { @MainActor in await ocrBatch(images) }
    }
  }

  @MainActor
  private func ocrBatch(_ images: [UIImage]) async {
    errorMessage = nil
    isReading = true
    let ingestor = PageIngestor()
    let hint = languageHint ?? book?.languageCode
    var built: [BatchReviewView.Page] = []
    var detected: String?
    for image in images {
      let result = try? await ingestor.recognize(image, languageHint: hint)
      let text = result?.text ?? ""
      built.append(.init(image: image, text: text))
      if detected == nil, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        detected = result?.detectedLanguageCode
      }
    }
    isReading = false
    guard built.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
      errorMessage = "No text found — flatten the pages, add light, and retake."
      return
    }
    step = .reviewBatch(built, OCRReviewView.matchLanguage(detected ?? ""))
  }
}
