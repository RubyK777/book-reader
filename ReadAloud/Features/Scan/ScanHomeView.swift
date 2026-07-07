import SwiftUI
import PhotosUI

/// Phase 1 home: pick a language, capture or import a page photo,
/// run OCR + sentence split, then push the Reader.
struct ScanHomeView: View {
    private static let languages: [(name: String, code: String)] = [
        ("French", "fr-FR"), ("Spanish", "es-ES"), ("German", "de-DE"),
        ("Italian", "it-IT"), ("Portuguese", "pt-PT"), ("Japanese", "ja-JP"),
        ("Korean", "ko-KR"), ("Chinese (Simplified)", "zh-Hans"), ("English", "en-US"),
    ]

    @AppStorage("targetLanguage") private var languageCode = "fr-FR"
    @State private var showCamera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var readerSentences: [String]?

    private let ocr = OCRService()
    private let splitter = SentenceSplitter()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "book.pages")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                Text("ReadAloud")
                    .font(.largeTitle.bold())
                Text("Photograph a book page,\nlisten sentence by sentence.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                Spacer()

                Picker("Language", selection: $languageCode) {
                    ForEach(Self.languages, id: \.code) { language in
                        Text(language.name).tag(language.code)
                    }
                }
                .pickerStyle(.menu)

                if isProcessing {
                    ProgressView("Reading page…")
                } else {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Scan a Page", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Import Photo", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding(24)
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    Task { await process(image) }
                }
                .ignoresSafeArea()
            }
            .onChange(of: photoItem) {
                guard let photoItem else { return }
                Task {
                    if let data = try? await photoItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await process(image)
                    }
                    self.photoItem = nil
                }
            }
            .navigationDestination(item: $readerSentences) { sentences in
                ReaderView(sentences: sentences, languageCode: languageCode)
            }
        }
    }

    @MainActor
    private func process(_ image: UIImage) async {
        isProcessing = true
        errorMessage = nil
        defer { isProcessing = false }

        do {
            let text = try await ocr.recognizeText(in: image, languageCode: languageCode)
            let sentences = splitter.split(text, languageCode: languageCode)
            if sentences.isEmpty {
                errorMessage = "No text found — try a flatter page with more light."
            } else {
                readerSentences = sentences
            }
        } catch {
            errorMessage = "Couldn't read the page: \(error.localizedDescription)"
        }
    }
}

// Allow [String] to drive navigationDestination(item:).
extension [String]: @retroactive Identifiable {
    public var id: String { joined(separator: "\u{1F}") }
}

#Preview {
    ScanHomeView()
}
