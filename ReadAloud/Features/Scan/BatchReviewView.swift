import SwiftUI
import SwiftData

/// Post-OCR review for a multi-page batch capture (docs/IMPROVEMENTS §3): page
/// through each captured page's recognized text, confirm one shared source
/// language, then persist them all into a single book in order. Reuses
/// `PageIngestor` (per-page) and `AssignBookView` (destination pick), mirroring
/// `OCRReviewView`'s single-page flow.
struct BatchReviewView: View {
  /// One captured page awaiting confirmation.
  struct Page: Identifiable {
    let id = UUID()
    let image: UIImage
    var text: String
  }

  let book: Book?
  let onRetake: () -> Void

  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  @Environment(AppRouter.self) private var router
  @Query(sort: \Book.createdAt, order: .reverse) private var books: [Book]

  @State private var pages: [Page]
  @State private var languageCode: String
  @State private var selection = 0
  @State private var showingAssign = false
  @State private var errorMessage: String?

  init(pages: [Page], languageCode: String, book: Book?, onRetake: @escaping () -> Void) {
    _pages = State(initialValue: pages)
    _languageCode = State(initialValue: languageCode)
    self.book = book
    self.onRetake = onRetake
  }

  /// Pages that actually carry text — only these are saved.
  private var savablePages: [Page] {
    pages.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
  }

  var body: some View {
    VStack(spacing: DesignSystem.Spacing.sm) {
      Picker("Source language", selection: $languageCode) {
        ForEach(LanguageCatalog.options, id: \.code) { lang in
          Text(lang.name).tag(lang.code)
        }
      }
      .pickerStyle(.menu)
      .padding(.horizontal, DesignSystem.Spacing.md)

      TabView(selection: $selection) {
        ForEach(Array(pages.enumerated()), id: \.element.id) { index, _ in
          pageEditor(index).tag(index)
        }
      }
      .tabViewStyle(.page(indexDisplayMode: .always))
      .indexViewStyle(.page(backgroundDisplayMode: .always))
    }
    .navigationTitle("Review \(pages.count) Pages")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Retake", action: onRetake)
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") { saveTapped() }
          .disabled(savablePages.isEmpty)
      }
    }
    .sheet(isPresented: $showingAssign) {
      AssignBookView(books: books, suggestedTitle: suggestedTitle) { chosen in
        showingAssign = false
        ingestAll(into: chosen)
      }
    }
    .alert("Couldn't save pages",
           isPresented: Binding(get: { errorMessage != nil },
                                set: { if !$0 { errorMessage = nil } })) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage ?? "")
    }
  }

  private func pageEditor(_ index: Int) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
        HStack {
          ProgressCounter(current: index + 1, total: pages.count, noun: "Page")
          Spacer()
          if pages[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Label("No text", systemImage: "exclamationmark.triangle")
              .font(.caption)
              .foregroundStyle(Theme.marigold)
          }
        }

        Image(uiImage: pages[index].image)
          .resizable()
          .scaledToFit()
          .frame(maxHeight: 180)
          .frame(maxWidth: .infinity)
          .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))

        TextEditor(text: $pages[index].text)
          .frame(minHeight: 200)
          .padding(DesignSystem.Spacing.xs)
          .overlay(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
            .stroke(Theme.cardStroke, lineWidth: 1))
      }
      .padding(.horizontal, DesignSystem.Spacing.md)
      .padding(.bottom, DesignSystem.Spacing.xl)
    }
  }

  /// Auto-title from the first savable page's opening words.
  private var suggestedTitle: String {
    String.titleSnippet(from: savablePages.first?.text ?? "")
  }

  private func saveTapped() {
    if let book {
      ingestAll(into: book)
    } else {
      showingAssign = true
    }
  }

  private func ingestAll(into targetBook: Book) {
    let cameFromLibrary = (book == nil)
    var ingestedAny = false
    for page in pages {
      let trimmed = page.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { continue }
      if (try? PageIngestor().ingest(page.image, text: page.text,
                                     languageCode: languageCode,
                                     into: targetBook, context: modelContext)) != nil {
        ingestedAny = true
      }
    }
    guard ingestedAny else {
      errorMessage = "No text to save. Edit a page or retake."
      return
    }
    Haptics.success()
    dismiss()
    // Land on the book so all the new pages are visible at once.
    if cameFromLibrary { router.libraryPath.append(targetBook) }
  }
}
