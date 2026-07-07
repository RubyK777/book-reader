import Foundation
import Vision
import NaturalLanguage
import UIKit

/// Recognized text plus the language it was detected in (BCP-47 / dominant).
struct OCRResult {
    let text: String
    let detectedLanguageCode: String
}

struct OCRService {
    /// Photo → recognized text, lines sorted top-to-bottom, language auto-detected.
    /// languageHint is BCP-47 (e.g. "fr-FR"); nil = let Vision auto-detect the script.
    func recognizeText(in image: UIImage, languageHint: String? = nil) async throws -> OCRResult {
        guard let cgImage = image.cgImage else { return OCRResult(text: "", detectedLanguageCode: "und") }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if let hint = languageHint {
            request.recognitionLanguages = [hint]
        } else {
            request.automaticallyDetectsLanguage = true
        }

        let handler = VNImageRequestHandler(cgImage: cgImage,
                                            orientation: CGImagePropertyOrientation(image.imageOrientation))
        try await Task.detached(priority: .userInitiated) {
            try handler.perform([request])
        }.value

        let observations = request.results ?? []
        // Vision's normalized coordinates have origin at bottom-left,
        // so higher midY = closer to the top of the page.
        let sorted = observations.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
        let text = sorted
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")

        // Vision has no reliable per-page language; name it from the assembled text.
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let detected = recognizer.dominantLanguage?.rawValue ?? "und"

        return OCRResult(text: text, detectedLanguageCode: detected)
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
