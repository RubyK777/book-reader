import Testing
@testable import ReadAloud

struct AudioIngestorTests {
    @Test func mapsSentencesToSegmentRangesByWordCount() {
        let segments = [
            TranscriptSegment(text: "Bonjour", start: 0.0, duration: 0.5),
            TranscriptSegment(text: "tout", start: 0.6, duration: 0.3),
            TranscriptSegment(text: "le", start: 1.0, duration: 0.2),
            TranscriptSegment(text: "monde", start: 1.3, duration: 0.4),
            TranscriptSegment(text: "Ça", start: 2.0, duration: 0.3),
            TranscriptSegment(text: "va", start: 2.4, duration: 0.3),
        ]
        let ranges = AudioIngestor.timings(for: ["Bonjour tout le monde", "Ça va"], segments: segments)

        #expect(ranges.count == 2)
        #expect(ranges[0].start == 0.0)
        #expect(isClose(ranges[0].end, 1.7))   // 4th word ends at 1.3 + 0.4
        #expect(ranges[1].start == 2.0)
        #expect(isClose(ranges[1].end, 2.7))   // 6th word ends at 2.4 + 0.3
    }

    private func isClose(_ a: Double?, _ b: Double, tol: Double = 0.0001) -> Bool {
        guard let a else { return false }
        return abs(a - b) < tol
    }

    @Test func clampsWhenSentencesHaveMoreWordsThanSegments() {
        let segments = [TranscriptSegment(text: "un", start: 0, duration: 1)]
        let ranges = AudioIngestor.timings(for: ["un deux trois"], segments: segments)
        #expect(ranges[0].start == 0)
        #expect(ranges[0].end == 1)     // clamped to the last available segment
    }

    @Test func emptySegmentsYieldNilTimings() {
        let ranges = AudioIngestor.timings(for: ["a b", "c"], segments: [])
        #expect(ranges.allSatisfy { $0.start == nil && $0.end == nil })
    }

    @Test func mapProducesPerWordRangesAndTimings() {
        let segments = [
            TranscriptSegment(text: "Bonjour", start: 0.0, duration: 0.5),
            TranscriptSegment(text: "monde", start: 0.6, duration: 0.4),
        ]
        let mapped = AudioIngestor.map(sentences: ["Bonjour monde"], segments: segments)

        #expect(mapped.count == 1)
        #expect(mapped[0].words.count == 2)
        #expect(mapped[0].words[0].location == 0)   // "Bonjour"
        #expect(mapped[0].words[0].length == 7)
        #expect(mapped[0].words[0].start == 0.0)
        #expect(mapped[0].words[1].location == 8)   // "monde"
        #expect(mapped[0].words[1].length == 5)
        #expect(mapped[0].words[1].start == 0.6)
    }
}
