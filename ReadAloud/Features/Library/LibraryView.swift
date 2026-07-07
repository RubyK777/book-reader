import SwiftUI
import SwiftData
import UIKit

/// Home tab: the shelf of scanned books, newest first.
/// Scan launches the capture-first flow; `+` creates an empty book.
struct LibraryView: View {
  @Environment(AppRouter.self) private var router
  @Environment(\.modelContext) private var modelContext
  @Query(sort: \Book.createdAt, order: .reverse) private var books: [Book]

  @State private var isScanPresented = false
  @State private var isNewBookPresented = false
  @State private var bookToEdit: Book?
  @State private var bookPendingDeletion: Book?

  var body: some View {
    Group {
      if books.isEmpty {
        emptyState
      } else {
        bookList
      }
    }
    .navigationTitle("Library")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button { isScanPresented = true } label: {
          Label("Scan", systemImage: "camera")
        }
      }
      ToolbarItem(placement: .topBarTrailing) {
        Button { isNewBookPresented = true } label: {
          Label("New Book", systemImage: "plus")
        }
      }
    }
    .sheet(isPresented: $isScanPresented) {
      ScanFlowView(book: nil)
    }
    .sheet(isPresented: $isNewBookPresented) {
      BookFormView(mode: .create)
    }
    .sheet(item: $bookToEdit) { book in
      BookFormView(mode: .edit(book))
    }
    .confirmationDialog(
      bookPendingDeletion.map { "Delete \"\($0.title)\"?" } ?? "Delete book?",
      isPresented: Binding(
        get: { bookPendingDeletion != nil },
        set: { if !$0 { bookPendingDeletion = nil } }
      ),
      titleVisibility: .visible,
      presenting: bookPendingDeletion
    ) { book in
      Button("Delete", role: .destructive) { delete(book) }
      Button("Cancel", role: .cancel) {}
    } message: { book in
      let count = book.pages.count
      Text("Removes \(count) page\(count == 1 ? "" : "s"). Saved words are kept.")
    }
  }

  private var bookList: some View {
    List {
      ForEach(books) { book in
        NavigationLink(value: book) {
          BookRow(book: book)
        }
        .swipeActions {
          Button(role: .destructive) { bookPendingDeletion = book } label: {
            Label("Delete", systemImage: "trash")
          }
        }
        .contextMenu {
          Button { bookToEdit = book } label: { Label("Edit", systemImage: "pencil") }
          Button(role: .destructive) { bookPendingDeletion = book } label: {
            Label("Delete", systemImage: "trash")
          }
        }
      }
    }
  }

  private var emptyState: some View {
    ContentUnavailableView {
      Label("Scan your first page", systemImage: "book.pages")
    } description: {
      Text("Photograph a book page to hear it read aloud.")
    } actions: {
      Button { isScanPresented = true } label: {
        Label("Scan", systemImage: "camera")
      }
      .buttonStyle(.borderedProminent)
    }
  }

  private func delete(_ book: Book) {
    modelContext.delete(book)
    bookPendingDeletion = nil
  }
}

/// One shelf row — cover thumbnail, title, language + page count.
private struct BookRow: View {
  let book: Book

  var body: some View {
    HStack(spacing: DesignSystem.Spacing.md) {
      CoverThumbnail(data: coverData, placeholder: "book.closed")
      VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
        Text(book.title)
          .font(.body)
          .lineLimit(2)
        Text(subtitle)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, DesignSystem.Spacing.xs)
  }

  private var coverData: Data? {
    if let cover = book.coverImageData { return cover }
    return book.pages.min { $0.orderIndex < $1.orderIndex }?.imageData
  }

  private var subtitle: String {
    let count = book.pages.count
    let language = SupportedLanguage.name(for: book.languageCode)
    return "\(language) · \(count) page\(count == 1 ? "" : "s")"
  }
}

/// Small book/page cover, decoded off the main actor and downscaled.
/// Shared by Library and Book detail rows.
struct CoverThumbnail: View {
  let data: Data?
  var placeholder: String = "book.closed"

  @State private var image: UIImage?

  var body: some View {
    Group {
      if let image {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
      } else {
        Image(systemName: placeholder)
          .font(.title2)
          .foregroundStyle(.secondary)
      }
    }
    .frame(width: 52, height: 68)
    .background(Color(.secondarySystemBackground))
    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
    .task(id: data) { await load() }
  }

  private func load() async {
    guard let data else { image = nil; return }
    let decoded = await Task.detached(priority: .utility) {
      UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 156, height: 204))
    }.value
    image = decoded
  }
}
