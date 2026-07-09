import Foundation
import SwiftData

/// Versioned schema so model changes migrate cleanly.
///
/// V1 (below) is the **frozen snapshot** of the models as they shipped to
/// Ruby's device before the real-world-learning pivot (PIVOT_PLAN.md §6) —
/// nested copies that must never change again. The live classes in
/// `Models.swift` are V2: `Book.kindRaw` (source kinds), the new `Annotation`
/// model, and `Sentence.learningAssets` / `Sentence.annotations`. V1→V2 is a
/// lightweight migration: added entity, added optional attributes, and one
/// added non-optional attribute with a default (`kindRaw`).
enum ReadAloudSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Book.self, ScanPage.self, Sentence.self, SavedWord.self]
    }

    @Model
    final class Book {
        var title: String
        var languageCode: String?
        var translationLanguage: String?
        var createdAt: Date

        @Attribute(.externalStorage)
        var coverImageData: Data?

        @Relationship(deleteRule: .cascade, inverse: \ScanPage.book)
        var pages: [ScanPage] = []

        init(title: String) {
            self.title = title
            self.createdAt = .now
        }
    }

    @Model
    final class ScanPage {
        @Attribute(.externalStorage)
        var imageData: Data
        var rawText: String
        var orderIndex: Int
        var scannedAt: Date
        var lastOpenedAt: Date?
        var book: Book?

        @Relationship(deleteRule: .cascade, inverse: \Sentence.page)
        var sentences: [Sentence] = []

        init(imageData: Data, rawText: String, orderIndex: Int) {
            self.imageData = imageData
            self.rawText = rawText
            self.orderIndex = orderIndex
            self.scannedAt = .now
        }
    }

    @Model
    final class Sentence {
        var text: String
        var orderIndex: Int
        var isBookmarked: Bool
        var userNote: String?
        var translatedText: String?
        var page: ScanPage?
        var srs: SRSState?

        init(text: String, orderIndex: Int) {
            self.text = text
            self.orderIndex = orderIndex
            self.isBookmarked = false
        }
    }

    @Model
    final class SavedWord {
        var word: String
        var contextSentence: String
        var languageCode: String
        var userNote: String?
        var savedAt: Date
        var srs: SRSState?

        init(word: String, contextSentence: String, languageCode: String) {
            self.word = word
            self.contextSentence = contextSentence
            self.languageCode = languageCode
            self.savedAt = .now
        }
    }
}

/// V2 — the live models in `Models.swift` (pivot restructure, PIVOT_PLAN.md §6).
enum ReadAloudSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Book.self, ScanPage.self, Sentence.self, SavedWord.self, Annotation.self]
    }
}

/// Current schema the container opens against.
typealias ReadAloudSchema = ReadAloudSchemaV2

enum ReadAloudMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [ReadAloudSchemaV1.self, ReadAloudSchemaV2.self]
    }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: ReadAloudSchemaV1.self,
                      toVersion: ReadAloudSchemaV2.self)]
    }
}
