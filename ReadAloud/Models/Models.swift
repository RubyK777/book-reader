import Foundation
import SwiftData

// MARK: - Book (a physical book the user is reading)
@Model
final class Book {
    var title: String
    var languageCode: String?       // BCP-47, e.g. "fr-FR" — nil until the first scan confirms it (capture-first)
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

// MARK: - Sentence (unit of listening)
@Model
final class Sentence {
    var text: String
    var orderIndex: Int             // position within page
    var isBookmarked: Bool
    var userNote: String?
    var page: ScanPage?

    // Review / SRS state (nil until bookmarked)
    var srs: SRSState?

    init(text: String, orderIndex: Int) {
        self.text = text
        self.orderIndex = orderIndex
        self.isBookmarked = false
    }
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
