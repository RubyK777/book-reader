import SwiftUI
import UIKit

/// The system dictionary panel for a term (PHASE3_DESIGN §5). Presented as a
/// sheet; when no definition exists it shows a Manage Dictionaries download flow.
struct DictionaryView: UIViewControllerRepresentable {
    let term: String

    func makeUIViewController(context: Context) -> UIReferenceLibraryViewController {
        UIReferenceLibraryViewController(term: term)
    }

    func updateUIViewController(_ controller: UIReferenceLibraryViewController, context: Context) {}
}

/// Identifiable term wrapper so a `String` can drive `.sheet(item:)`.
struct DictionaryTerm: Identifiable { let term: String; var id: String { term } }
