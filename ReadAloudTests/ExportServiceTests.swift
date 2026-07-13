import Foundation
import SwiftData
import Testing
@testable import ReadAloud

/// ExportService fidelity: what goes into the store comes back out of the JSON
/// backup — book / page / sentence / word fields, SRS state, and stable
/// ordering (pages & sentences sorted by `orderIndex` regardless of insert
/// order). Page images are intentionally excluded (text/vocab export, not a
/// binary backup), so we don't assert on them.
@MainActor
struct ExportServiceTests {

    private func inMemoryContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(versionedSchema: ReadAloudSchema.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func decode(_ data: Data) throws -> ExportService.Export {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601   // must mirror the encoder
        return try decoder.decode(ExportService.Export.self, from: data)
    }

    @Test func roundTripsBooksSentencesAndWords() throws {
        let context = try inMemoryContext()

        let book = Book(title: "Le Petit Prince")
        book.languageCode = "fr-FR"
        book.translationLanguage = "en-US"

        // Pages inserted out of order to prove the export sorts by orderIndex.
        let pageOne = ScanPage(rawText: "p1", orderIndex: 1)
        let pageZero = ScanPage(rawText: "p0", orderIndex: 0)
        pageOne.book = book
        pageZero.book = book

        // Two sentences on page 0, also out of order.
        let greeting = Sentence(text: "Bonjour.", orderIndex: 1)
        greeting.isBookmarked = true
        greeting.userNote = "a greeting"
        greeting.translatedText = "Hello."
        greeting.srs = SRSState()
        greeting.page = pageZero
        let fox = Sentence(text: "Le renard.", orderIndex: 0)
        fox.page = pageZero

        // Saved words are word/phrase annotations now (V5); the export still
        // surfaces them under `savedWords`.
        let word = Annotation(type: .word, text: "renard",
                              contextSentence: "Le renard.", languageCode: "fr-FR")
        word.userNote = "fox"
        word.srs = SRSState()

        for model in [book, pageZero, pageOne] as [any PersistentModel] { context.insert(model) }
        context.insert(greeting); context.insert(fox); context.insert(word)
        try context.save()

        let export = try decode(ExportService.makeJSON(in: context))

        // Book-level fields survive.
        #expect(export.books.count == 1)
        let bookDTO = try #require(export.books.first)
        #expect(bookDTO.title == "Le Petit Prince")
        #expect(bookDTO.languageCode == "fr-FR")
        #expect(bookDTO.translationLanguage == "en-US")

        // Pages come out sorted; sentences live on page 0.
        #expect(bookDTO.pages.map(\.orderIndex) == [0, 1])
        // Sentences carry no orderIndex in the DTO — their array position is the
        // order, so this sequence proves the export sorted them (fox=0, then
        // greeting=1) rather than emitting insertion order.
        let pageDTO = try #require(bookDTO.pages.first)
        #expect(pageDTO.sentences.map(\.text) == ["Le renard.", "Bonjour."])

        // The bookmarked sentence keeps every field, including SRS.
        let greetingDTO = try #require(pageDTO.sentences.last)
        #expect(greetingDTO.isBookmarked)
        #expect(greetingDTO.note == "a greeting")
        #expect(greetingDTO.translatedText == "Hello.")
        #expect(greetingDTO.srs != nil)

        // Saved words round-trip with their note + SRS.
        #expect(export.savedWords.count == 1)
        let wordDTO = try #require(export.savedWords.first)
        #expect(wordDTO.word == "renard")
        #expect(wordDTO.note == "fox")
        #expect(wordDTO.srs != nil)
    }

    @Test func emptyStoreExportsEmptyCollections() throws {
        let context = try inMemoryContext()
        let export = try decode(ExportService.makeJSON(in: context))
        #expect(export.books.isEmpty)
        #expect(export.savedWords.isEmpty)
    }
}
