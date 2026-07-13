import SwiftUI
import SwiftData
import UIKit

/// Home tab: a bookshelf of scanned sources, newest first — each stands
/// cover-out like a paperback on a shelf, and tapping one *opens* it (a zoom
/// transition into its pages, wired in `RootView`). Scan launches the
/// capture-first flow; `+` creates an empty book.
struct LibraryView: View {
  @Environment(AppRouter.self) private var router
  @Environment(\.modelContext) private var modelContext
  @Query(sort: \Book.createdAt, order: .reverse) private var books: [Book]

  /// Shared with `RootView`'s `BookDetailView` destination so a tapped cover
  /// zooms open into the book.
  var bookNamespace: Namespace.ID

  @State private var isScanPresented = false
  @State private var bookToEdit: Book?
  @State private var bookPendingDeletion: Book?

  /// First-run onboarding — shown once when the shelf is empty (UX §7).
  @AppStorage("hasSeenIntro") private var hasSeenIntro = false
  @State private var showWelcome = false
  @State private var startScanAfterWelcome = false

  /// Books per shelf row.
  private let columns = 3

  var body: some View {
    Group {
      if books.isEmpty {
        emptyState
      } else {
        shelf
      }
    }
    .navigationTitle("Library")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button { isScanPresented = true } label: {
          Label("Scan", systemImage: "camera")
        }
        .symbolEffect(.wiggle, options: .repeat(.periodic(delay: 4)), isActive: books.isEmpty)
      }
    }
    .onAppear {
      if !hasSeenIntro && books.isEmpty { showWelcome = true }
    }
    .fullScreenCover(isPresented: $showWelcome, onDismiss: {
      if startScanAfterWelcome {
        startScanAfterWelcome = false
        isScanPresented = true
      }
    }) {
      WelcomeView { startScan in
        hasSeenIntro = true
        startScanAfterWelcome = startScan
        showWelcome = false
      }
    }
    .sheet(isPresented: $isScanPresented) {
      ScanFlowView(book: nil)
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

  // MARK: - Shelf

  private var shelf: some View {
    ScrollView {
      LazyVStack(spacing: DesignSystem.Spacing.xl) {
        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
          shelfRow(row)
        }
      }
      .padding(.vertical, DesignSystem.Spacing.lg)
    }
  }

  /// The books chunked into rows of `columns`.
  private var rows: [[Book]] {
    stride(from: 0, to: books.count, by: columns).map {
      Array(books[$0 ..< min($0 + columns, books.count)])
    }
  }

  private func shelfRow(_ row: [Book]) -> some View {
    VStack(spacing: DesignSystem.Spacing.sm) {
      HStack(alignment: .bottom, spacing: DesignSystem.Spacing.md) {
        ForEach(row) { book in tile(book) }
        // Keep covers left-aligned and same-sized on a short final row.
        if row.count < columns {
          ForEach(0 ..< (columns - row.count), id: \.self) { _ in
            Color.clear.frame(maxWidth: .infinity)
          }
        }
      }
      shelfLedge
    }
    .padding(.horizontal, DesignSystem.Spacing.screenMargin)
  }

  /// The wooden lip each row of books stands on.
  private var shelfLedge: some View {
    RoundedRectangle(cornerRadius: 2)
      .fill(Theme.cardStroke)
      .frame(height: DesignSystem.Spacing.xs)
      .frame(maxWidth: .infinity)
      .shadow(color: .black.opacity(0.15), radius: 2, y: 2)
  }

  private func tile(_ book: Book) -> some View {
    NavigationLink(value: book) {
      BookCover(book: book)
        .matchedTransitionSource(id: book.persistentModelID, in: bookNamespace)
    }
    .buttonStyle(PressableScaleButtonStyle())
    .frame(maxWidth: .infinity)
    .contextMenu {
      Button { bookToEdit = book } label: { Label("Edit", systemImage: "pencil") }
      Button(role: .destructive) { bookPendingDeletion = book } label: {
        Label("Delete", systemImage: "trash")
      }
    }
  }

  private var emptyState: some View {
    AnimatedEmptyState(
      title: "Scan your first page",
      message: "Photograph a page, sign, or menu — then hear it read aloud, word by word.",
      systemImage: "book.pages",
      tint: Theme.coral
    ) {
      Button { isScanPresented = true } label: {
        Label("Scan", systemImage: "camera")
      }
      .buttonStyle(SpringyProminentButtonStyle(tint: Theme.coral))
      .padding(.horizontal, DesignSystem.Spacing.xl)
    }
  }

  private func delete(_ book: Book) {
    modelContext.delete(book)
    bookPendingDeletion = nil
  }
}

/// A single book standing cover-out on the shelf: its real cover photo (first
/// page) if it has one, otherwise a generated paperback in the kind's color
/// with the title in serif. Faked binding + drop shadow give it depth.
private struct BookCover: View {
  let book: Book

  @State private var image: UIImage?

  private var coverData: Data? { book.coverImageData }

  private var hasPhoto: Bool { coverData != nil }

  var body: some View {
    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small, style: .continuous)
      .fill(book.kind.tint.gradient)
      .aspectRatio(2.0 / 3.0, contentMode: .fit)
      .overlay { face }
      .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small, style: .continuous))
      .overlay { binding }
      .overlay(alignment: .topTrailing) { kindBadge }
      .overlay(
        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small, style: .continuous)
          .strokeBorder(.black.opacity(0.12), lineWidth: 0.5)
      )
      .shadow(color: .black.opacity(0.30), radius: 5, x: 3, y: 5)
      .task(id: coverData) { await load() }
      .accessibilityElement()
      .accessibilityLabel(accessibilityLabel)
      .accessibilityAddTraits(.isButton)
  }

  @ViewBuilder
  private var face: some View {
    if let image {
      // Real cover photo speaks for itself — the title reveals on open
      // (BookDetailView's large nav title), keeping the shelf clean.
      Image(uiImage: image)
        .resizable()
        .scaledToFill()
    } else {
      VStack(spacing: DesignSystem.Spacing.sm) {
        Image(systemName: book.kind.systemImage)
          .font(.title3)
          .foregroundStyle(.white.opacity(0.9))
        Text(book.title)
          .font(.callout.weight(.semibold))
          .fontDesign(Theme.sentenceDesign)
          .foregroundStyle(.white)
          .lineLimit(4)
          .multilineTextAlignment(.center)
          .minimumScaleFactor(0.75)
      }
      .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
      .padding(DesignSystem.Spacing.md)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  /// The leading "binding" — a soft dark gradient where a paperback's spine sits.
  private var binding: some View {
    HStack(spacing: 0) {
      LinearGradient(colors: [.black.opacity(0.28), .black.opacity(0.04), .clear],
                     startPoint: .leading, endPoint: .trailing)
        .frame(width: 12)
      Spacer(minLength: 0)
    }
    .allowsHitTesting(false)
  }

  /// Non-book sources (sign/menu/screenshot) wear a small kind badge on a
  /// photo cover; generated covers already show the kind icon in the middle.
  @ViewBuilder
  private var kindBadge: some View {
    if hasPhoto, book.kind != .book {
      Image(systemName: book.kind.systemImage)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(book.kind.tint)
        .padding(DesignSystem.Spacing.xs)
        .background(Circle().fill(.white.opacity(0.92)))
        .padding(DesignSystem.Spacing.xs)
    }
  }

  private var accessibilityLabel: String {
    let count = book.pages.count
    let pages = "\(count) page\(count == 1 ? "" : "s")"
    return book.kind == .book
      ? "\(book.title), \(pages)"
      : "\(book.title), \(book.kind.displayName), \(pages)"
  }

  private func load() async {
    guard let data = coverData else { image = nil; return }
    let decoded = await Task.detached(priority: .utility) {
      UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 400, height: 600))
    }.value
    image = decoded
  }
}

/// Small book/page cover, decoded off the main actor and downscaled.
/// Shared by Book detail and Book form rows.
struct CoverThumbnail: View {
  let data: Data?
  var placeholder: String = "book.closed"
  var tint: Color = .secondary

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
          .foregroundStyle(tint)
      }
    }
    .frame(width: 48, height: 64)
    .background(Palette.soft(tint))
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
