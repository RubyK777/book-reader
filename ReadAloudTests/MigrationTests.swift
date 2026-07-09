import Foundation
import SwiftData
import Testing
@testable import ReadAloud

/// PIVOT_PLAN Phase 1 acceptance: a V1 store (Ruby's device) opens through the
/// migration plan with data intact, and the V2 additions behave.
struct MigrationTests {

    /// Build a store with the frozen V1 schema, reopen it with the migration
    /// plan against V2, and verify nothing was lost and defaults applied.
    @Test func v1StoreMigratesToV2() throws {
        let url = URL.temporaryDirectory
            .appending(path: "migration-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        // Populate a V1 store the way the shipped app would have.
        do {
            let config = ModelConfiguration(url: url)
            let container = try ModelContainer(
                for: Schema(versionedSchema: ReadAloudSchemaV1.self),
                configurations: config)
            let context = ModelContext(container)

            let book = ReadAloudSchemaV1.Book(title: "Le Petit Prince")
            book.languageCode = "fr-FR"
            let page = ReadAloudSchemaV1.ScanPage(
                imageData: Data([0xFF]), rawText: "raw", orderIndex: 0)
            page.book = book
            let sentence = ReadAloudSchemaV1.Sentence(
                text: "Je n'arrive pas à y croire.", orderIndex: 0)
            sentence.isBookmarked = true
            sentence.srs = SRSState()
            sentence.page = page
            let word = ReadAloudSchemaV1.SavedWord(
                word: "croire", contextSentence: sentence.text, languageCode: "fr-FR")
            context.insert(book)
            context.insert(word)
            try context.save()
        }

        // Reopen through the migration plan (V1 → V2 lightweight).
        let config = ModelConfiguration(url: url)
        let container = try ModelContainer(
            for: Schema(versionedSchema: ReadAloudSchemaV2.self),
            migrationPlan: ReadAloudMigrationPlan.self,
            configurations: config)
        let context = ModelContext(container)

        let books = try context.fetch(FetchDescriptor<Book>())
        #expect(books.count == 1)
        let book = try #require(books.first)
        #expect(book.title == "Le Petit Prince")
        #expect(book.languageCode == "fr-FR")
        #expect(book.kind == .book)   // added attribute got its default

        let sentences = try context.fetch(FetchDescriptor<Sentence>())
        #expect(sentences.count == 1)
        let sentence = try #require(sentences.first)
        #expect(sentence.isBookmarked)
        #expect(sentence.srs != nil)
        #expect(sentence.learningAssets == nil)
        #expect(sentence.annotations.isEmpty)

        let words = try context.fetch(FetchDescriptor<SavedWord>())
        #expect(words.count == 1)
        #expect(words.first?.word == "croire")

        // V2 additions work against the migrated store.
        let annotation = Annotation(
            type: .phrase, text: "arriver à",
            contextSentence: sentence.text, languageCode: "fr-FR",
            intent: .use)
        annotation.srs = SRSState()
        annotation.sentence = sentence
        context.insert(annotation)
        sentence.learningAssets = LearningAssets(
            chunks: [.init(text: "Je n'arrive pas", gloss: "I can't manage")],
            isGenerated: true, modelVersion: "test")
        try context.save()

        let annotations = try context.fetch(FetchDescriptor<Annotation>())
        #expect(annotations.count == 1)
        #expect(annotations.first?.type == .phrase)
        #expect(annotations.first?.intent == .use)
        #expect(annotations.first?.sentence?.persistentModelID == sentence.persistentModelID)
        #expect(sentence.learningAssets?.chunks.first?.gloss == "I can't manage")
    }

    /// Raw-string enum bridging survives unknown values (forward compatibility).
    @Test func annotationEnumBridging() {
        let annotation = Annotation(
            type: .word, text: "croire",
            contextSentence: "ctx", languageCode: "fr-FR")
        #expect(annotation.type == .word)
        #expect(annotation.intent == nil)
        annotation.intent = .pronounce
        #expect(annotation.intentRaw == "pronounce")
        annotation.typeRaw = "not-a-type"
        #expect(annotation.type == .phrase)   // documented fallback
    }
}
