import SwiftUI
import SwiftData
import PhotosUI

/// Post-OCR, pre-persist review: edit the recognized text and confirm the
/// source language before anything is saved. On "Use" the (edited) text is
/// split with the confirmed language and ingested; `book == nil` first opens
/// an assign step to pick or quick-create the destination Book.
struct OCRReviewView: View {
  let image: UIImage
  let result: OCRResult
  let book: Book?
  let onRetake: () -> Void

  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  @Environment(AppRouter.self) private var router
  @Query(sort: \Book.createdAt, order: .reverse) private var books: [Book]

  @State private var text: String
  @State private var languageCode: String
  @State private var showingAssign = false
  @State private var showingDigest = false
  @State private var errorMessage: String?

  /// One line per detected item for the quick-translate digest — newlines match
  /// a menu/sign's layout; fall back to sentence splitting for prose.
  private var digestLines: [String] {
    let byLine = text.split(separator: "\n")
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
    if byLine.count >= 2 { return byLine }
    return SentenceSplitter().split(text, languageCode: languageCode)
  }

  init(image: UIImage, result: OCRResult, book: Book?, onRetake: @escaping () -> Void) {
    self.image = image
    self.result = result
    self.book = book
    self.onRetake = onRetake
    _text = State(initialValue: result.text)
    _languageCode = State(initialValue: Self.matchLanguage(result.detectedLanguageCode))
  }

  private var isEmpty: Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    Form {
      Section {
        Picker("Language", selection: $languageCode) {
          ForEach(LanguageCatalog.options, id: \.code) { lang in
            Text(lang.name).tag(lang.code)
          }
        }
      } header: {
        Text("Source language")
      } footer: {
        Text("Detected automatically — correct it here if it's wrong.")
      }
      Section("Page text") {
        TextEditor(text: $text)
          .frame(minHeight: 240)
      }
      Section {
        Button {
          showingDigest = true
        } label: {
          Label("Translate & Listen", systemImage: "translate")
        }
        .disabled(isEmpty)
      } footer: {
        Text("See each line translated and hear it — without saving. Handy for a sign or menu.")
      }
    }
    .navigationTitle("Review Page")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Retake", action: onRetake)
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Use") { useTapped() }
          .disabled(isEmpty)
      }
    }
    .sheet(isPresented: $showingAssign) {
      AssignBookView(books: books, suggestedTitle: suggestedTitle) { chosen in
        showingAssign = false
        performIngest(into: chosen)
      }
    }
    .sheet(isPresented: $showingDigest) {
      ScanDigestView(lines: digestLines, languageCode: languageCode)
    }
    .alert("Couldn't save page",
           isPresented: Binding(get: { errorMessage != nil },
                                set: { if !$0 { errorMessage = nil } })) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage ?? "")
    }
  }

  /// Auto-title for Quick Scan sources: the first few scanned words.
  private var suggestedTitle: String { String.titleSnippet(from: text) }

  // MARK: Actions

  private func useTapped() {
    if let book {
      performIngest(into: book)
    } else {
      showingAssign = true
    }
  }

  private func performIngest(into targetBook: Book) {
    do {
      let page = try PageIngestor().ingest(image, text: text,
                                           languageCode: languageCode,
                                           into: targetBook, context: modelContext)
      Haptics.success()
      let cameFromLibrary = (book == nil)
      dismiss()
      // Library entry: Book isn't on the stack yet, so push it before the page.
      if cameFromLibrary { router.libraryPath.append(targetBook) }
      router.libraryPath.append(page)
    } catch {
      errorMessage = "No text to save. Edit the text or retake the page."
    }
  }

  /// Map a detected BCP-47 code onto a recognizable language option, matching
  /// on the language subtag ("fr" → "fr-FR"). Falls back to the device's
  /// native language, then the first option, when the detection is unmatched.
  static func matchLanguage(_ detected: String) -> String {
    let options = LanguageCatalog.options
    if let exact = options.first(where: { $0.code == detected }) {
      return exact.code
    }
    let base = String(detected.prefix(2)).lowercased()
    if let loose = options.first(where: { $0.code.lowercased().hasPrefix(base) }) {
      return loose.code
    }
    return options.first(where: { $0.code.hasPrefix(LanguageCatalog.deviceDefaultNative) })?.code
      ?? options.first?.code ?? "en-US"
  }
}

/// Assign step for the Library entry path: Quick Scan (no book — a
/// lightweight source auto-titled from the text, PIVOT_PLAN Phase 1), pick an
/// existing book, or quick-create one by title. Reused by the batch flow.
struct AssignBookView: View {
  let books: [Book]
  let suggestedTitle: String
  let onAssign: (Book) -> Void

  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  @State private var newTitle = ""
  @State private var coverItem: PhotosPickerItem?
  @State private var coverData: Data?

  private var trimmedTitle: String {
    newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Button {
            createQuick()
          } label: {
            Label("Save as quick scan", systemImage: SourceKind.quickScan.systemImage)
              .foregroundStyle(.primary)
          }
        } header: {
          Text("Quick scan — no book")
        } footer: {
          Text("A single capture — a sign, menu, or screenshot. Saved as “\(suggestedTitle)”.")
        }

        Section {
          TextField("Title", text: $newTitle)
          PhotosPicker(selection: $coverItem, matching: .images) {
            HStack(spacing: DesignSystem.Spacing.md) {
              CoverThumbnail(data: coverData, placeholder: "photo")
              Text(coverData == nil ? "Choose cover (optional)" : "Change cover")
            }
          }
          if coverData != nil {
            Button("Remove cover", role: .destructive) {
              coverData = nil
              coverItem = nil
            }
          }
        } header: {
          Text("New book")
        } footer: {
          Text("If you don't choose a cover, this scanned page is used.")
        }
        if !books.isEmpty {
          Section("Or add to an existing book") {
            ForEach(books) { book in
              Button { onAssign(book) } label: {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                  Text(book.title)
                    .foregroundStyle(.primary)
                  Text("\(LanguageCatalog.name(for: book.languageCode)) · \(book.pages.count) pages")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }
            }
          }
        }
      }
      .navigationTitle("Save Page To")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Create") { createNew() }
            .disabled(trimmedTitle.isEmpty)
        }
      }
      .onChange(of: coverItem) { _, item in loadCover(item) }
    }
  }

  private func createNew() {
    let book = Book(title: trimmedTitle)
    book.coverImageData = coverData
    modelContext.insert(book)
    onAssign(book)
  }

  private func loadCover(_ item: PhotosPickerItem?) {
    guard let item else { return }
    Task { coverData = await item.loadCoverJPEG() }
  }

  private func createQuick() {
    let source = Book(title: suggestedTitle.isEmpty ? SourceKind.quickScan.displayName : suggestedTitle,
                      kind: .quickScan)
    modelContext.insert(source)
    onAssign(source)
  }
}
