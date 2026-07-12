import Foundation
import SwiftData

// MARK: - SourceKind (what kind of real-world source a Book container holds)

/// PIVOT_PLAN.md §6: `Book` generalizes into a source container. Two buckets:
/// a `book` keeps title/cover ceremony and holds many pages; everything else is
/// a `quickScan` — a single real-world capture (sign, menu, screenshot, …).
/// The finer sign/menu/screenshot split was cosmetic-only and was dropped.
enum SourceKind: String, Codable, CaseIterable {
    case book, quickScan

    /// Decode a stored raw value, folding the legacy kinds
    /// (`sign`/`menu`/`screenshot`/`other`) into `.quickScan` so older captures
    /// keep working without a migration.
    static func normalized(_ raw: String) -> SourceKind {
        if let known = SourceKind(rawValue: raw) { return known }
        return raw == book.rawValue ? .book : .quickScan
    }

    var displayName: String {
        switch self {
        case .book: "Book"
        case .quickScan: "Quick scan"
        }
    }

    var systemImage: String {
        switch self {
        case .book: "book.closed"
        case .quickScan: "doc.text.viewfinder"
        }
    }
}

// MARK: - Book (a source container: physical book, sign, menu, screenshot…)
@Model
final class Book {
    var title: String
    var languageCode: String?       // BCP-47 source language, e.g. "fr-FR" — nil until the first scan confirms it (capture-first)
    var translationLanguage: String?  // BCP-47 target; nil = translation OFF for this book (TRANSLATION_DESIGN §2)
    var createdAt: Date

    /// Stored raw so SwiftData migrates it as a plain string (PIVOT_PLAN §6).
    var kindRaw: String = SourceKind.book.rawValue

    @Attribute(.externalStorage)
    var coverImageData: Data?

    @Relationship(deleteRule: .cascade, inverse: \ScanPage.book)
    var pages: [ScanPage] = []

    var kind: SourceKind {
        get { SourceKind.normalized(kindRaw) }
        set { kindRaw = newValue.rawValue }
    }

    init(title: String, kind: SourceKind = .book) {
        self.title = title
        self.createdAt = .now
        self.kindRaw = kind.rawValue
    }
}

// MARK: - ScanPage (one captured photo)
@Model
final class ScanPage {
    @Attribute(.externalStorage)
    var imageData: Data             // original photo, for re-reading later
    var rawText: String             // full OCR output
    var orderIndex: Int             // page order within book
    var scannedAt: Date
    var lastOpenedAt: Date?         // drives Resume; nil until first opened
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

// MARK: - Sentence (unit of listening; parent of all learning annotations)
@Model
final class Sentence {
    var text: String
    var orderIndex: Int             // position within page
    var isBookmarked: Bool
    var userNote: String?
    var translatedText: String?     // persisted translation of `text`; nil = not yet translated (TRANSLATION_DESIGN §2)
    var page: ScanPage?

    // Review / SRS state (nil until bookmarked)
    var srs: SRSState?

    /// AI/user learning assets for this sentence (PIVOT_PLAN §6). Generated
    /// lazily on first Sentence Learning View visit; never regenerated —
    /// sentence text is immutable once assets derive from it (D6).
    var learningAssets: LearningAssets?

    @Relationship(deleteRule: .cascade, inverse: \Annotation.sentence)
    var annotations: [Annotation] = []

    init(text: String, orderIndex: Int) {
        self.text = text
        self.orderIndex = orderIndex
        self.isBookmarked = false
    }
}

// MARK: - Annotation (a saved learning item, parented to a Sentence)

/// What kind of learning unit the user saved (PIVOT_PLAN D3) — inferred from
/// the selection gesture, never asked.
enum AnnotationType: String, Codable, CaseIterable {
    case word, phrase, sentence, grammar
}

/// Optional save intent (PIVOT_PLAN D3/D11): collected, shown in the Notebook,
/// editable later. Does NOT route review cards in v1 (D11).
enum SaveIntent: String, Codable, CaseIterable {
    case remember, pronounce, use, confused

    var displayName: String {
        switch self {
        case .remember: "Remember"
        case .pronounce: "Pronounce"
        case .use: "Use later"
        case .confused: "Confused"
        }
    }
}

/// The single save unit of the pivot (PIVOT_PLAN §6): saved words, phrases,
/// whole sentences, and grammar points are typed annotations on a Sentence.
/// `SavedWord` remains for pre-pivot data until the Saved tab is ported.
@Model
final class Annotation {
    /// Stored raw strings so migration stays lightweight.
    var typeRaw: String
    var intentRaw: String?

    /// The saved text itself (word, phrase chunk, or the whole sentence).
    var text: String
    /// Location of `text` within the parent sentence, when it is a fragment.
    var rangeLocation: Int?
    var rangeLength: Int?

    /// Snapshot of the parent sentence — survives page/sentence deletion.
    var contextSentence: String
    var languageCode: String

    var userNote: String?
    var userExample: String?
    var tags: [String] = []

    var isConfusing: Bool = false
    var isResolved: Bool = false
    var savedAt: Date

    /// Lifecycle rule (PIVOT_PLAN Phase 4): suspended items keep their SRS
    /// history but leave the due queue until unsuspended.
    var isSuspended: Bool = false
    /// Confusion workflow: the generated explanation attempt (D7 provenance —
    /// it's model-authored and the user can edit or clear it).
    var aiExplanation: String?

    var srs: SRSState?
    var sentence: Sentence?

    var type: AnnotationType {
        get { AnnotationType(rawValue: typeRaw) ?? .phrase }
        set { typeRaw = newValue.rawValue }
    }

    var intent: SaveIntent? {
        get { intentRaw.flatMap(SaveIntent.init(rawValue:)) }
        set { intentRaw = newValue?.rawValue }
    }

    init(type: AnnotationType, text: String, contextSentence: String,
         languageCode: String, intent: SaveIntent? = nil) {
        self.typeRaw = type.rawValue
        self.text = text
        self.contextSentence = contextSentence
        self.languageCode = languageCode
        self.intentRaw = intent?.rawValue
        self.savedAt = .now
    }
}

// MARK: - LearningAssets (understand-section content, embedded value type)

/// Phrase breakdown + key vocabulary + one grammar point for a sentence
/// (PIVOT_PLAN §6). Produced by a `LearningAssetsProviding` service (D10) or
/// authored by the user in the fallback view; provenance is tracked per D7.
struct LearningAssets: Codable {
    struct Chunk: Codable, Hashable {
        var text: String    // the chunk as it appears in the sentence
        var gloss: String   // its meaning, in the user's native language
    }

    struct VocabItem: Codable, Hashable {
        var term: String
        var meaning: String
    }

    var chunks: [Chunk] = []
    var keyVocab: [VocabItem] = []
    var grammarPoint: String?

    /// D7 provenance: true when a model produced this; user edits stay marked.
    var isGenerated: Bool = false
    var modelVersion: String?
    var generatedAt: Date?
    /// Set when the user edits generated content (D7) — optional so values
    /// stored before this field decode cleanly.
    var userEditedAt: Date?
}

// MARK: - SavedWord (vocabulary item)
@Model
final class SavedWord {
    var word: String
    var contextSentence: String     // snapshot, survives page deletion
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

// MARK: - SRSState (SM-2 spaced repetition, embedded value type)
struct SRSState: Codable {
    var repetitions: Int = 0
    var easeFactor: Double = 2.5
    var intervalDays: Int = 0
    var dueDate: Date = .now

    // quality: 0 (fail) ... 5 (perfect)
    mutating func review(quality: Int) {
        if quality < 3 {
            repetitions = 0
            intervalDays = 1
        } else {
            switch repetitions {
            case 0: intervalDays = 1
            case 1: intervalDays = 6
            default: intervalDays = Int(Double(intervalDays) * easeFactor)
            }
            repetitions += 1
        }
        easeFactor = max(1.3, easeFactor + 0.1
            - Double(5 - quality) * (0.08 + Double(5 - quality) * 0.02))
        dueDate = Calendar.current.date(byAdding: .day,
                                        value: intervalDays, to: .now) ?? .now
    }
}
