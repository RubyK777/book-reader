import SwiftUI
import PhotosUI
import UIKit

extension PhotosPickerItem {
    /// Load this picked photo as a cover-sized JPEG (nil if it can't be read).
    /// Shared by the New-Book form and the scan-assign cover pickers.
    func loadCoverJPEG() async -> Data? {
        guard let data = try? await loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return nil }
        return ImageProcessor.coverJPEG(image)
    }
}
