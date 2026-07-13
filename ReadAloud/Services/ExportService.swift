import Foundation
import SwiftData

/// Serializes the user's library to a JSON backup (books + sentences + saved
/// words + notes + review state). Page images are excluded — this is a
/// text/vocabulary export, not a full binary backup.
enum ExportService {
    struct Export: Codable {
        let exportedAt: Date
        let books: [BookDTO]
        let savedWords: [WordDTO]
    }
    struct BookDTO: Codable {
        let title: String
        let languageCode: String?
        let translationLanguage: String?
        let createdAt: Date
        let pages: [PageDTO]
    }
    struct PageDTO: Codable {
        let orderIndex: Int
        let scannedAt: Date
        let sentences: [SentenceDTO]
    }
    struct SentenceDTO: Codable {
        let text: String
        let translatedText: String?
        let isBookmarked: Bool
        let note: String?
        let srs: SRSState?
    }
    struct WordDTO: Codable {
        let word: String
        let contextSentence: String
        let languageCode: String
        let note: String?
        let savedAt: Date
        let srs: SRSState?
    }

    @MainActor
    static func makeJSON(in context: ModelContext) throws -> Data {
        let books = (try? context.fetch(
            FetchDescriptor<Book>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        // Saved words & phrases are word/phrase annotations (V5, DECISIONS #63);
        // export them under the stable `savedWords` key so backups don't change shape.
        let words = (try? context.fetch(
            FetchDescriptor<Annotation>(sortBy: [SortDescriptor(\.savedAt)])))?
            .filter { $0.type == .word || $0.type == .phrase } ?? []

        let export = Export(
            exportedAt: Date(),
            books: books.map { book in
                BookDTO(
                    title: book.title,
                    languageCode: book.languageCode,
                    translationLanguage: book.translationLanguage,
                    createdAt: book.createdAt,
                    pages: book.pages.sorted { $0.orderIndex < $1.orderIndex }.map { page in
                        PageDTO(
                            orderIndex: page.orderIndex,
                            scannedAt: page.scannedAt,
                            sentences: page.sentences.sorted { $0.orderIndex < $1.orderIndex }.map { s in
                                SentenceDTO(text: s.text, translatedText: s.translatedText,
                                            isBookmarked: s.isBookmarked, note: s.userNote, srs: s.srs)
                            })
                    })
            },
            savedWords: words.map { w in
                WordDTO(word: w.text, contextSentence: w.contextSentence, languageCode: w.languageCode,
                        note: w.userNote, savedAt: w.savedAt, srs: w.srs)
            })

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(export)
    }

    /// Writes the JSON to a temp file and returns its URL, for the share sheet.
    @MainActor
    static func writeExport(in context: ModelContext) throws -> URL {
        let data = try makeJSON(in: context)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadAloud-Export.json")
        try data.write(to: url, options: .atomic)
        return url
    }
}
