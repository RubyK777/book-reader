import UIKit

/// Downscales captured photos before persisting them (keeps the store small).
enum ImageProcessor {
    /// Page image for `ScanPage.imageData`: longest side ≤ maxDimension, JPEG at `quality`.
    static func storageJPEG(_ image: UIImage, maxDimension: CGFloat = 2048, quality: CGFloat = 0.7) -> Data {
        let scaled = downscale(image, maxDimension: maxDimension)
        return scaled.jpegData(compressionQuality: quality) ?? Data()
    }

    /// Smaller image for `Book.coverImageData` (thumbnail-grade).
    static func coverJPEG(_ image: UIImage) -> Data {
        let scaled = downscale(image, maxDimension: 1024)
        return scaled.jpegData(compressionQuality: 0.7) ?? Data()
    }

    /// Aspect-preserving downscale of the longest side; returns the original if already small.
    private static func downscale(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return image }

        let scale = maxDimension / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
