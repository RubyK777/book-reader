import Foundation
import SwiftData

/// Versioned schema so model changes migrate cleanly.
///
/// V1 (below) is the **frozen snapshot** of the models as they shipped to
/// Ruby's device before the real-world-learning pivot (product design §6) —
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

/// V2 — **frozen snapshot** of the pivot restructure as installed on Ruby's
/// iPhone on 2026-07-09 (DECISIONS #35). Codable value structs are part of the
/// schema fingerprint, so this freeze carries its own `LearningAssets` copy
/// (without `userEditedAt`, which V3 added). Never change these.
enum ReadAloudSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Book.self, ScanPage.self, Sentence.self, SavedWord.self, Annotation.self]
    }

    struct LearningAssets: Codable {
        struct Chunk: Codable, Hashable {
            var text: String
            var gloss: String
        }
        struct VocabItem: Codable, Hashable {
            var term: String
            var meaning: String
        }
        var chunks: [Chunk] = []
        var keyVocab: [VocabItem] = []
        var grammarPoint: String?
        var isGenerated: Bool = false
        var modelVersion: String?
        var generatedAt: Date?
    }

    @Model
    final class Book {
        var title: String
        var languageCode: String?
        var translationLanguage: String?
        var createdAt: Date
        var kindRaw: String = SourceKind.book.rawValue

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
        var learningAssets: LearningAssets?

        @Relationship(deleteRule: .cascade, inverse: \Annotation.sentence)
        var annotations: [Annotation] = []

        init(text: String, orderIndex: Int) {
            self.text = text
            self.orderIndex = orderIndex
            self.isBookmarked = false
        }
    }

    @Model
    final class Annotation {
        var typeRaw: String
        var intentRaw: String?
        var text: String
        var rangeLocation: Int?
        var rangeLength: Int?
        var contextSentence: String
        var languageCode: String
        var userNote: String?
        var userExample: String?
        var tags: [String] = []
        var isConfusing: Bool = false
        var isResolved: Bool = false
        var savedAt: Date
        var srs: SRSState?
        var sentence: Sentence?

        init(typeRaw: String, text: String, contextSentence: String, languageCode: String) {
            self.typeRaw = typeRaw
            self.text = text
            self.contextSentence = contextSentence
            self.languageCode = languageCode
            self.savedAt = .now
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

/// V3 — **frozen snapshot** as installed on Ruby's iPhone 2026-07-09 (second
/// deploy). Adds `LearningAssets.userEditedAt` over V2. Never change these.
enum ReadAloudSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Book.self, ScanPage.self, Sentence.self, SavedWord.self, Annotation.self]
    }

    struct LearningAssets: Codable {
        struct Chunk: Codable, Hashable {
            var text: String
            var gloss: String
        }
        struct VocabItem: Codable, Hashable {
            var term: String
            var meaning: String
        }
        var chunks: [Chunk] = []
        var keyVocab: [VocabItem] = []
        var grammarPoint: String?
        var isGenerated: Bool = false
        var modelVersion: String?
        var generatedAt: Date?
        var userEditedAt: Date?
    }

    @Model
    final class Book {
        var title: String
        var languageCode: String?
        var translationLanguage: String?
        var createdAt: Date
        var kindRaw: String = SourceKind.book.rawValue

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
        var learningAssets: LearningAssets?

        @Relationship(deleteRule: .cascade, inverse: \Annotation.sentence)
        var annotations: [Annotation] = []

        init(text: String, orderIndex: Int) {
            self.text = text
            self.orderIndex = orderIndex
            self.isBookmarked = false
        }
    }

    @Model
    final class Annotation {
        var typeRaw: String
        var intentRaw: String?
        var text: String
        var rangeLocation: Int?
        var rangeLength: Int?
        var contextSentence: String
        var languageCode: String
        var userNote: String?
        var userExample: String?
        var tags: [String] = []
        var isConfusing: Bool = false
        var isResolved: Bool = false
        var savedAt: Date
        var srs: SRSState?
        var sentence: Sentence?

        init(typeRaw: String, text: String, contextSentence: String, languageCode: String) {
            self.typeRaw = typeRaw
            self.text = text
            self.contextSentence = contextSentence
            self.languageCode = languageCode
            self.savedAt = .now
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

/// V4 — the live models in `Models.swift`. Adds `Annotation.isSuspended`
/// (lifecycle rule), `Annotation.aiExplanation` (confusion workflow),
/// `Annotation.translation` (cached meaning), **drops `ScanPage.imageData`**
/// (page photos are transient OCR fodder now — DECISIONS #54), and adds the
/// **audio-source** fields — `ScanPage.audioData/audioDuration`,
/// `Sentence.audioStart/audioEnd`, `SourceKind.conversation` (AUDIO_LEARNING_DESIGN).
/// Reset fresh (no prod users) rather than a staged migration.
/// V4 — **frozen snapshot** as installed on Ruby's iPhone. Book/ScanPage/
/// Sentence/Annotation reference the live classes (they're unchanged since V4);
/// `SavedWord` is frozen here as its own nested copy because V5 removes it from
/// the live models (the port into `Annotation`), and this snapshot must keep the
/// definition it shipped with. Never change these.
enum ReadAloudSchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Book.self, ScanPage.self, Sentence.self, SavedWord.self, Annotation.self]
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

/// V5 — the live models in `Models.swift`. **Drops `SavedWord`**: saved words &
/// phrases are now `Annotation`s (type `.word` / `.phrase`), unifying the save
/// path, the Saved tab, and the Notebook (one model, one review case). Reset
/// fresh (no prod users) rather than a data-preserving migration — DECISIONS #63.
enum ReadAloudSchemaV5: VersionedSchema {
    static let versionIdentifier = Schema.Version(5, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Book.self, ScanPage.self, Sentence.self, Annotation.self]
    }
}

/// Current schema the container opens against.
typealias ReadAloudSchema = ReadAloudSchemaV5

enum ReadAloudMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [ReadAloudSchemaV1.self, ReadAloudSchemaV2.self,
         ReadAloudSchemaV3.self, ReadAloudSchemaV4.self, ReadAloudSchemaV5.self]
    }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: ReadAloudSchemaV1.self,
                      toVersion: ReadAloudSchemaV2.self),
         .lightweight(fromVersion: ReadAloudSchemaV2.self,
                      toVersion: ReadAloudSchemaV3.self),
         .lightweight(fromVersion: ReadAloudSchemaV3.self,
                      toVersion: ReadAloudSchemaV4.self),
         // Removing the SavedWord entity is lightweight-eligible; in practice
         // Ruby reinstalls (no prod users), so a fresh V5 store is created and
         // this stage never runs.
         .lightweight(fromVersion: ReadAloudSchemaV4.self,
                      toVersion: ReadAloudSchemaV5.self)]
    }
}
