import Foundation
import Vision
import UIKit

struct OCRService {
    /// Photo → recognized text, lines sorted top-to-bottom.
    /// languageCode is BCP-47 (e.g. "fr-FR") — see PROJECT_PLAN.md §5.1.
    func recognizeText(in image: UIImage, languageCode: String) async throws -> String {
        guard let cgImage = image.cgImage else { return "" }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = [languageCode]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage,
                                            orientation: CGImagePropertyOrientation(image.imageOrientation))
        try await Task.detached(priority: .userInitiated) {
            try handler.perform([request])
        }.value

        let observations = request.results ?? []
        // Vision's normalized coordinates have origin at bottom-left,
        // so higher midY = closer to the top of the page.
        let sorted = observations.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
        return sorted
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
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
