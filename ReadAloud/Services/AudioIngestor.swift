import Foundation
import SwiftData

/// Persists a transcribed audio clip as a `.conversation` source: one `ScanPage`
/// carrying the recording, its `Sentence`s carrying segment timings for
/// real-audio playback (AUDIO_LEARNING_DESIGN §7). The timing map is a pure,
/// testable function; persistence mirrors `PageIngestor`.
struct AudioIngestor {
    var splitter = SentenceSplitter()

    /// Map each sentence to a `[start, end]` time range by walking the recognizer's
    /// per-word segments in order, consuming one segment per word. Light text
    /// edits stay aligned; heavy edits drift (documented limitation, §7).
    static func timings(for sentences: [String],
                        segments: [TranscriptSegment]) -> [(start: Double?, end: Double?)] {
        guard !segments.isEmpty else { return sentences.map { _ in (nil, nil) } }
        var cursor = 0
        return sentences.map { sentence in
            let words = sentence.split(whereSeparator: { $0.isWhitespace }).count
            guard words > 0, cursor < segments.count else { return (nil, nil) }
            let start = segments[cursor].start
            let lastIndex = min(cursor + words - 1, segments.count - 1)
            let end = segments[lastIndex].end
            cursor = lastIndex + 1
            return (start, end)
        }
    }

    /// Split the confirmed transcript, attach timings, and persist a new
    /// conversation source. Returns the created book (nothing persists on failure).
    @MainActor
    func ingest(audioData: Data,
                duration: Double,
                text: String,
                title: String,
                languageCode: String,
                translationLanguage: String?,
                segments: [TranscriptSegment],
                context: ModelContext) throws -> Book {
        let parts = splitter.split(text, languageCode: languageCode)
        guard !parts.isEmpty else { throw IngestError.noTextFound }

        let ranges = Self.timings(for: parts, segments: segments)

        let book = Book(title: title, kind: .conversation)
        book.languageCode = languageCode
        book.translationLanguage = translationLanguage

        let page = ScanPage(rawText: text, orderIndex: 0)
        page.audioData = audioData
        page.audioDuration = duration
        page.sentences = parts.enumerated().map { index, sentenceText in
            let sentence = Sentence(text: sentenceText, orderIndex: index)
            sentence.audioStart = ranges[index].start
            sentence.audioEnd = ranges[index].end
            return sentence
        }

        context.insert(book)
        context.insert(page)
        book.pages.append(page)
        try context.save()
        return book
    }
}
