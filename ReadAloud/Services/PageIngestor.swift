import Foundation
import SwiftData
import UIKit
import LearningKit

enum IngestError: Error { case noTextFound }

/// Turns a captured page into a persisted `ScanPage` + `Sentence` rows.
/// Split into two calls so the scan flow can OCR first, let the user edit, then persist.
struct PageIngestor {
    var ocr = OCRService()
    var splitter = SentenceSplitter()

    /// Step 1: run OCR only (no persistence). `languageHint` = book's language on the Add-Page path.
    func recognize(_ image: UIImage, languageHint: String?) async throws -> OCRResult {
        try await ocr.recognizeText(in: image, languageHint: languageHint)
    }

    /// Step 2: split the user-confirmed text and persist the page into `book`.
    @MainActor
    func ingest(_ image: UIImage,
                text: String,
                languageCode: String,
                into book: Book,
                context: ModelContext) throws -> ScanPage {
        let parts = splitter.split(text, languageCode: languageCode)
        guard !parts.isEmpty else { throw IngestError.noTextFound }

        let orderIndex = (book.pages.map(\.orderIndex).max() ?? -1) + 1
        // The captured photo is not persisted — pages are just OCR fodder.
        let page = ScanPage(rawText: text, orderIndex: orderIndex)
        page.sentences = parts.enumerated().map { Sentence(text: $1, orderIndex: $0) }

        if book.languageCode == nil { book.languageCode = languageCode }
        // Keep one image per source: the first page becomes the cover unless the
        // user already chose one.
        if book.coverImageData == nil { book.coverImageData = ImageProcessor.coverJPEG(image) }

        context.insert(page)
        book.pages.append(page)
        try context.save()
        return page
    }
}
