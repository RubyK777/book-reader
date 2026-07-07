import SwiftUI
import SwiftData

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
  @State private var errorMessage: String?

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
      AssignBookView(books: books) { chosen in
        showingAssign = false
        performIngest(into: chosen)
      }
    }
    .alert("Couldn't save page",
           isPresented: Binding(get: { errorMessage != nil },
                                set: { if !$0 { errorMessage = nil } })) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage ?? "")
    }
  }

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
  private static func matchLanguage(_ detected: String) -> String {
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

/// Assign step for the Library entry path: pick an existing book or
/// quick-create one by title. The chosen Book is handed back for ingest.
private struct AssignBookView: View {
  let books: [Book]
  let onAssign: (Book) -> Void

  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  @State private var newTitle = ""

  private var trimmedTitle: String {
    newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("New book") {
          TextField("Title", text: $newTitle)
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
    }
  }

  private func createNew() {
    let book = Book(title: trimmedTitle)
    modelContext.insert(book)
    onAssign(book)
  }
}
