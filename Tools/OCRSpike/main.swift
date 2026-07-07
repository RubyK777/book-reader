// OCR spike — validates the riskiest part of ReadAloud (PROJECT_PLAN.md §7)
// before any iOS code is written. Runs the same Vision + NaturalLanguage
// pipeline the app will use, on photos of real book pages.
//
// Usage:
//   swift Tools/OCRSpike/main.swift <lang> <image> [image...]
//   swift Tools/OCRSpike/main.swift fr-FR Fixtures/*.jpg

import Foundation
import Vision
import NaturalLanguage
import AppKit

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: main.swift <bcp47-lang e.g. fr-FR> <image> [image...]")
    exit(1)
}
let language = args[1]
let imagePaths = Array(args[2...])

func recognizeText(in url: URL, language: String) throws -> [VNRecognizedTextObservation] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = [language]
    request.usesLanguageCorrection = true

    let handler = VNImageRequestHandler(url: url)
    try handler.perform([request])
    return request.results ?? []
}

// Same ordering problem the app must solve for two-column layouts (§7):
// sort observations top-to-bottom using Vision's normalized coordinates
// (origin bottom-left), joining lines into one text block.
func assembleText(_ observations: [VNRecognizedTextObservation]) -> (text: String, meanConfidence: Double) {
    let sorted = observations.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
    var lines: [String] = []
    var confidences: [Double] = []
    for obs in sorted {
        guard let candidate = obs.topCandidates(1).first else { continue }
        lines.append(candidate.string)
        confidences.append(Double(candidate.confidence))
    }
    let mean = confidences.isEmpty ? 0 : confidences.reduce(0, +) / Double(confidences.count)
    return (lines.joined(separator: " "), mean)
}

func splitSentences(_ text: String, language: String) -> [String] {
    let tokenizer = NLTokenizer(unit: .sentence)
    tokenizer.setLanguage(NLLanguage(rawValue: String(language.prefix(2))))
    tokenizer.string = text
    var sentences: [String] = []
    tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
        let s = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.isEmpty { sentences.append(s) }
        return true
    }
    return sentences
}

print("OCR spike — language: \(language), \(imagePaths.count) image(s)\n")

for path in imagePaths {
    let url = URL(fileURLWithPath: path)
    print(String(repeating: "=", count: 60))
    print("📄 \(url.lastPathComponent)")
    let start = Date()
    do {
        let observations = try recognizeText(in: url, language: language)
        let (text, confidence) = assembleText(observations)
        let sentences = splitSentences(text, language: language)
        let elapsed = Date().timeIntervalSince(start)

        print(String(format: "   %d lines, mean confidence %.2f, %.1fs", observations.count, confidence, elapsed))
        print("   \(sentences.count) sentences:\n")
        for (i, sentence) in sentences.enumerated() {
            print("   [\(i + 1)] \(sentence)")
        }
    } catch {
        print("   ⚠️ failed: \(error.localizedDescription)")
    }
    print()
}
