import SwiftUI
import SwiftData

/// Pages of one book, ordered by `orderIndex`. Optional Resume header,
/// reorder via Edit mode, swipe-to-delete, and an Add Page scan entry point.
struct BookDetailView: View {
  @Bindable var book: Book

  @Environment(AppRouter.self) private var router
  @Environment(\.modelContext) private var modelContext

  @State private var isAddPagePresented = false
  @State private var isEditFormPresented = false
  @State private var pagePendingDeletion: ScanPage?

  var body: some View {
    Group {
      if book.pages.isEmpty {
        emptyState
      } else {
        pageList
      }
    }
    .navigationTitle(book.title)
    .navigationBarTitleDisplayMode(.large)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Button { isEditFormPresented = true } label: {
            Label("Edit Book", systemImage: "pencil")
          }
        } label: {
          Image(systemName: "ellipsis.circle")
        }
      }
      if !book.pages.isEmpty {
        ToolbarItem(placement: .topBarTrailing) { EditButton() }
      }
    }
    .safeAreaInset(edge: .bottom) {
      if !book.pages.isEmpty {
        addPageButton
          .padding(DesignSystem.Spacing.md)
          .frame(maxWidth: .infinity)
          .background(.bar)
      }
    }
    .sheet(isPresented: $isAddPagePresented) {
      ScanFlowView(book: book)
    }
    .sheet(isPresented: $isEditFormPresented) {
      BookFormView(mode: .edit(book))
    }
    .confirmationDialog(
      "Delete this page?",
      isPresented: Binding(
        get: { pagePendingDeletion != nil },
        set: { if !$0 { pagePendingDeletion = nil } }
      ),
      titleVisibility: .visible,
      presenting: pagePendingDeletion
    ) { page in
      Button("Delete", role: .destructive) { deletePage(page) }
      Button("Cancel", role: .cancel) {}
    } message: { _ in
      Text("Removes this page and its sentences. Saved words are kept.")
    }
  }

  private var pageList: some View {
    List {
      if let resume = resumePage {
        Section {
          Button { open(resume) } label: {
            Label("Resume · Page \(pageNumber(resume))", systemImage: "play.circle.fill")
          }
        }
      }

      Section {
        ForEach(sortedPages) { page in
          Button { open(page) } label: { pageRow(page) }
            .buttonStyle(.plain)
            .swipeActions {
              Button(role: .destructive) { pagePendingDeletion = page } label: {
                Label("Delete", systemImage: "trash")
              }
            }
        }
        .onMove(perform: move)
      }
    }
  }

  private var emptyState: some View {
    ContentUnavailableView {
      Label("No pages yet", systemImage: "doc.text")
    } description: {
      Text("Add a page to start reading.")
    } actions: {
      addPageButton
    }
  }

  private var addPageButton: some View {
    Button { isAddPagePresented = true } label: {
      Label("Add Page", systemImage: "camera")
    }
    .buttonStyle(.borderedProminent)
  }

  private func pageRow(_ page: ScanPage) -> some View {
    HStack(spacing: DesignSystem.Spacing.md) {
      CoverThumbnail(data: page.imageData, placeholder: "doc.text.image")
      VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
        Text("Page \(pageNumber(page)) · \(page.sentences.count) sentence\(page.sentences.count == 1 ? "" : "s")")
          .font(.body)
        Text(page.scannedAt, format: .dateTime.month().day())
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Image(systemName: "chevron.right")
        .font(.footnote)
        .foregroundStyle(.tertiary)
    }
  }

  // MARK: - Data helpers

  private var sortedPages: [ScanPage] {
    book.pages.sorted { $0.orderIndex < $1.orderIndex }
  }

  private var resumePage: ScanPage? {
    book.pages
      .filter { $0.lastOpenedAt != nil }
      .max { ($0.lastOpenedAt ?? .distantPast) < ($1.lastOpenedAt ?? .distantPast) }
  }

  private func pageNumber(_ page: ScanPage) -> Int {
    (sortedPages.firstIndex(of: page) ?? 0) + 1
  }

  private func open(_ page: ScanPage) {
    page.lastOpenedAt = .now
    router.libraryPath.append(page)
  }

  private func move(from source: IndexSet, to destination: Int) {
    var pages = sortedPages
    pages.move(fromOffsets: source, toOffset: destination)
    for (index, page) in pages.enumerated() {
      page.orderIndex = index
    }
  }

  private func deletePage(_ page: ScanPage) {
    modelContext.delete(page)
    pagePendingDeletion = nil
    let remaining = book.pages
      .filter { $0.persistentModelID != page.persistentModelID }
      .sorted { $0.orderIndex < $1.orderIndex }
    for (index, remainingPage) in remaining.enumerated() {
      remainingPage.orderIndex = index
    }
  }
}
