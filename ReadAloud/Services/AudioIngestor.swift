import Foundation
import SwiftData
import LearningKit

/// Persists a transcribed audio clip as a `.conversation` source: one `ScanPage`
/// carrying the recording, its `Sentence`s carrying segment timings for
/// real-audio playback (AUDIO_LEARNING_DESIGN §7). The timing map is a pure,
/// testable function; persistence mirrors `PageIngestor`.
struct AudioIngestor {
    var splitter = SentenceSplitter()

    /// A sentence's overall range plus its per-word karaoke timings.
    struct SentenceTiming {
        let start: Double?
        let end: Double?
        let words: [WordTiming]
    }

    /// Walk the recognizer's per-word segments in order (one per word token) to
    /// produce each sentence's range and its word timings. Light text edits stay
    /// aligned; heavy edits drift (documented limitation, §7).
    static func map(sentences: [String], segments: [TranscriptSegment]) -> [SentenceTiming] {
        guard !segments.isEmpty else {
            return sentences.map { _ in SentenceTiming(start: nil, end: nil, words: []) }
        }
        var cursor = 0
        return sentences.map { sentence in
            var words: [WordTiming] = []
            for range in tokenRanges(in: sentence) {
                guard cursor < segments.count else { break }
                let segment = segments[cursor]
                words.append(WordTiming(start: segment.start, end: segment.end,
                                        location: range.location, length: range.length))
                cursor += 1
            }
            return SentenceTiming(start: words.first?.start, end: words.last?.end, words: words)
        }
    }

    /// Sentence-level `[start, end]` only (for callers/tests that skip word timings).
    static func timings(for sentences: [String],
                        segments: [TranscriptSegment]) -> [(start: Double?, end: Double?)] {
        map(sentences: sentences, segments: segments).map { ($0.start, $0.end) }
    }

    /// Word (NSRange) boundaries within a sentence's text.
    private static func tokenRanges(in text: String) -> [NSRange] {
        var ranges: [NSRange] = []
        let ns = text as NSString
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length),
                               options: .byWords) { _, range, _, _ in
            ranges.append(range)
        }
        return ranges
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

        let mapped = Self.map(sentences: parts, segments: segments)

        let book = Book(title: title, kind: .conversation)
        book.languageCode = languageCode
        book.translationLanguage = translationLanguage

        let page = ScanPage(rawText: text, orderIndex: 0)
        page.audioData = audioData
        page.audioDuration = duration
        page.sentences = parts.enumerated().map { index, sentenceText in
            let sentence = Sentence(text: sentenceText, orderIndex: index)
            sentence.audioStart = mapped[index].start
            sentence.audioEnd = mapped[index].end
            sentence.wordTimings = mapped[index].words.isEmpty ? nil : mapped[index].words
            return sentence
        }

        context.insert(book)
        context.insert(page)
        book.pages.append(page)
        try context.save()
        return book
    }
}
