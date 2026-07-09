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

        // Reopen through the migration plan (V1 → V2 → V3 lightweight).
        let config = ModelConfiguration(url: url)
        let container = try ModelContainer(
            for: Schema(versionedSchema: ReadAloudSchema.self),
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

    /// The store Ruby's iPhone actually has (V2, installed 2026-07-09) opens
    /// through the V2 → V3 stage with annotations and learning assets intact —
    /// DECISIONS #35: Codable struct changes fingerprint a new schema version.
    @Test func v2StoreMigratesToV3() throws {
        let url = URL.temporaryDirectory
            .appending(path: "migration-v2-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        // Populate a V2 store the way the on-device build did: a scanned
        // sentence with generated assets and a saved phrase annotation.
        do {
            let config = ModelConfiguration(url: url)
            let container = try ModelContainer(
                for: Schema(versionedSchema: ReadAloudSchemaV2.self),
                configurations: config)
            let context = ModelContext(container)

            let book = ReadAloudSchemaV2.Book(title: "Signs")
            book.kindRaw = "sign"
            let page = ReadAloudSchemaV2.ScanPage(
                imageData: Data([0xFF]), rawText: "raw", orderIndex: 0)
            page.book = book
            let sentence = ReadAloudSchemaV2.Sentence(
                text: "Défense de stationner devant la porte", orderIndex: 0)
            sentence.page = page
            sentence.learningAssets = ReadAloudSchemaV2.LearningAssets(
                chunks: [.init(text: "Défense de", gloss: "It is forbidden to")],
                grammarPoint: "défense de + infinitive",
                isGenerated: true, modelVersion: "apple-foundation-models-26")
            let annotation = ReadAloudSchemaV2.Annotation(
                typeRaw: "phrase", text: "défense de",
                contextSentence: sentence.text, languageCode: "fr-FR")
            annotation.intentRaw = "use"
            annotation.srs = SRSState()
            annotation.sentence = sentence
            context.insert(book)
            context.insert(annotation)
            try context.save()
        }

        // Reopen through the plan — the V2 → V3 leg.
        let config = ModelConfiguration(url: url)
        let container = try ModelContainer(
            for: Schema(versionedSchema: ReadAloudSchema.self),
            migrationPlan: ReadAloudMigrationPlan.self,
            configurations: config)
        let context = ModelContext(container)

        let books = try context.fetch(FetchDescriptor<Book>())
        #expect(books.first?.kind == .sign)

        let sentences = try context.fetch(FetchDescriptor<Sentence>())
        let sentence = try #require(sentences.first)
        let assets = try #require(sentence.learningAssets)
        #expect(assets.chunks.first?.gloss == "It is forbidden to")
        #expect(assets.grammarPoint == "défense de + infinitive")
        #expect(assets.isGenerated)
        #expect(assets.userEditedAt == nil)   // V3 addition defaults empty

        let annotations = try context.fetch(FetchDescriptor<Annotation>())
        let annotation = try #require(annotations.first)
        #expect(annotation.type == .phrase)
        #expect(annotation.intent == .use)
        #expect(annotation.sentence?.persistentModelID == sentence.persistentModelID)

        // V3 write works: mark the assets user-edited.
        sentence.learningAssets?.userEditedAt = .now
        try context.save()
        #expect(sentence.learningAssets?.userEditedAt != nil)
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
