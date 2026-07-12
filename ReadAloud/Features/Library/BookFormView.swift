import SwiftUI
import SwiftData
import PhotosUI
import UIKit

/// Create or edit a book's metadata: title, optional cover, and —
/// only in edit mode — the source language (locked once the first page exists;
/// on create the language is auto-set from the first scan's detection).
struct BookFormView: View {
  enum Mode {
    case create
    case edit(Book)
  }

  let mode: Mode

  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss

  @State private var title: String
  @State private var kind: SourceKind
  @State private var languageCode: String
  @State private var coverData: Data?
  @State private var pickerItem: PhotosPickerItem?

  init(mode: Mode) {
    self.mode = mode
    switch mode {
    case .create:
      _title = State(initialValue: "")
      _kind = State(initialValue: .book)
      _languageCode = State(initialValue: LanguageCatalog.options.first?.code ?? "en-US")
      _coverData = State(initialValue: nil)
    case .edit(let book):
      _title = State(initialValue: book.title)
      _kind = State(initialValue: book.kind)
      _languageCode = State(initialValue: book.languageCode ?? LanguageCatalog.options.first?.code ?? "en-US")
      _coverData = State(initialValue: book.coverImageData)
    }
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker("Type", selection: $kind) {
            ForEach(SourceKind.allCases, id: \.self) { kind in
              Label(kind.displayName, systemImage: kind.systemImage).tag(kind)
            }
          }
        } footer: {
          Text("A book holds many pages; a quick scan is a single capture — a sign, menu, or screenshot.")
        }

        Section("Title") {
          TextField("Title", text: $title)
        }

        Section {
          PhotosPicker(selection: $pickerItem, matching: .images) {
            HStack(spacing: DesignSystem.Spacing.md) {
              CoverThumbnail(data: coverData, placeholder: "photo")
              Text(coverData == nil ? "Choose cover" : "Change cover")
            }
          }
          if coverData != nil {
            Button("Remove cover", role: .destructive) {
              coverData = nil
              pickerItem = nil
            }
          }
        } header: {
          Text("Cover")
        }

        languageSection
      }
      .navigationTitle("\(editingBook == nil ? "New" : "Edit") \(kind.displayName)")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { save() }
            .disabled(trimmedTitle.isEmpty)
        }
      }
      .onChange(of: pickerItem) { _, item in loadCover(item) }
    }
  }

  @ViewBuilder
  private var languageSection: some View {
    if let book = editingBook {
      let locked = !book.pages.isEmpty
      Section {
        Picker("Language", selection: $languageCode) {
          ForEach(LanguageCatalog.options, id: \.code) { language in
            Text(language.name).tag(language.code)
          }
        }
        .disabled(locked)
      } footer: {
        Text(locked
          ? "Language is locked after the first page."
          : "Language is set on the first scan.")
      }
    } else {
      Section {
        EmptyView()
      } footer: {
        Text("Language is set on the first scan.")
      }
    }
  }

  private var editingBook: Book? {
    if case .edit(let book) = mode { return book }
    return nil
  }

  private var trimmedTitle: String {
    title.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func save() {
    let name = trimmedTitle
    guard !name.isEmpty else { return }
    switch mode {
    case .create:
      let book = Book(title: name, kind: kind)
      book.coverImageData = coverData
      modelContext.insert(book)
    case .edit(let book):
      book.title = name
      book.kind = kind
      book.coverImageData = coverData
      if book.pages.isEmpty {
        book.languageCode = languageCode
      }
    }
    Haptics.success()
    dismiss()
  }

  private func loadCover(_ item: PhotosPickerItem?) {
    guard let item else { return }
    Task {
      guard let data = try? await item.loadTransferable(type: Data.self),
            let image = UIImage(data: data) else { return }
      coverData = ImageProcessor.coverJPEG(image)
    }
  }
}
